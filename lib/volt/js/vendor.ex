defmodule Volt.JS.Vendor do
  @moduledoc """
  Pre-bundle vendor (node_modules) dependencies for dev mode.

  Scans source files with `OXC.imports/2`, identifies bare specifiers
  (non-relative, non-URL), resolves them through module directories, and
  bundles each into a single ESM file with `OXC.bundle/2`.

  CJS packages (e.g. React) are automatically converted to ESM during
  bundling. `process.env.NODE_ENV` is replaced with `"development"`
  so conditional CJS branches resolve correctly.

  Bundled files are cached on disk in `_build/volt/vendor/`.
  """

  require Logger

  defp cache_dir do
    build_path = System.get_env("MIX_BUILD_PATH") || "_build"
    Path.join(build_path, "volt/vendor")
  end

  @doc """
  Scan source files and pre-bundle any bare npm imports.

  Returns a map of `specifier → vendor_path` for import rewriting.

  ## Options

    * `:root` — source directory to scan
    * `:node_modules` — path to node_modules (default: auto-detect)
    * `:resolve_dirs` — additional package directories to resolve from
    * `:force` — rebuild even if cached (default: `false`)
  """
  @spec prebundle(keyword()) :: {:ok, %{String.t() => String.t()}} | {:error, term()}
  def prebundle(opts) do
    root = Keyword.fetch!(opts, :root)
    force = Keyword.get(opts, :force, false)
    node_modules = opts[:node_modules] || NPM.Resolution.PackageResolver.find_node_modules(root)
    module_dirs = module_dirs(node_modules, Keyword.get(opts, :resolve_dirs, []))

    plugins = Keyword.get(opts, :plugins, [])

    with {:ok, specifiers} <- scan_bare_imports(root, plugins),
         :ok <- ensure_cache_dir() do
      vendor_map =
        specifiers
        |> Enum.map(&Volt.PluginRunner.prebundle_alias(plugins, &1))
        |> Enum.uniq()
        |> Enum.reduce(%{}, fn spec, acc ->
          case safe_bundle_vendor(spec, module_dirs, force, plugins) do
            {:ok, path} -> Map.put(acc, spec, path)
            {:error, _} -> acc
          end
        end)

      {:ok, vendor_map}
    end
  end

  @doc """
  Bundle a single vendor specifier on demand.

  Used by the dev server when a `/@vendor/` request arrives for a
  specifier that wasn't caught by `prebundle/1` (e.g. transitive
  dependency, or newly added import).
  """
  @spec bundle_on_demand(String.t(), String.t() | nil, keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def bundle_on_demand(specifier, node_modules, opts \\ []) do
    ensure_cache_dir()
    {plugins, resolve_dirs} = normalize_on_demand_opts(opts)
    module_dirs = module_dirs(node_modules, resolve_dirs)
    specifier = Volt.PluginRunner.prebundle_alias(plugins, specifier)

    case bundle_vendor(specifier, module_dirs, false, plugins) do
      {:ok, path} -> File.read(path)
      {:error, _} = error -> error
    end
  end

  @doc """
  Get the URL path for a vendor module.
  """
  @spec vendor_url(String.t()) :: String.t()
  def vendor_url(specifier) do
    "/@vendor/#{encode_specifier(specifier)}.js"
  end

  @doc """
  Read a pre-bundled vendor file by specifier.
  """
  @spec read(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def read(specifier) do
    path = cache_path(specifier)

    case File.read(path) do
      {:ok, _} = ok -> ok
      {:error, _} -> {:error, :not_found}
    end
  end

  # ── Scanning ──────────────────────────────────────────────────────

  defp scan_bare_imports(root, plugins) do
    source_files =
      Volt.JS.Extensions.scannable(plugins)
      |> Enum.flat_map(fn ext -> Path.wildcard(Path.join(root, "**/*" <> ext)) end)
      |> Enum.uniq()

    specifiers =
      Enum.flat_map(source_files, fn file ->
        with {:ok, source} <- File.read(file),
             {:ok, imports} <- extract_imports(source, file, plugins) do
          Enum.filter(imports, &NPM.Resolution.PackageResolver.bare?/1)
        else
          _ -> []
        end
      end)

    {:ok, specifiers}
  end

  defp extract_imports(source, path, plugins) do
    case Volt.PluginRunner.extract_imports(plugins, path, source, []) do
      {:ok, %{imports: imports}} -> {:ok, Enum.map(imports, fn {_type, spec} -> spec end)}
      nil -> OXC.imports(source, Path.basename(path))
      {:error, _} = error -> error
    end
  end

  # ── Bundling ──────────────────────────────────────────────────────

  defp safe_bundle_vendor(specifier, module_dirs, force, plugins) do
    bundle_vendor(specifier, module_dirs, force, plugins)
  rescue
    exception ->
      Logger.debug(
        "[Volt] Vendor prebundle skipped #{specifier}: #{Exception.message(exception)}"
      )

      {:error, exception}
  end

  defp bundle_vendor(specifier, module_dirs, force, plugins) do
    path = cache_path(specifier)

    if not force and File.regular?(path) do
      {:ok, path}
    else
      do_bundle_vendor(specifier, module_dirs, path, plugins)
    end
  end

  defp do_bundle_vendor(specifier, module_dirs, output_path, plugins) do
    case prebundle_entry(specifier, module_dirs, plugins) do
      {:ok, entry_path, project_root} ->
        bundle_opts = [
          cwd: project_root,
          format: :esm,
          conditions: Volt.JS.PackageResolver.browser_conditions(),
          modules: module_dirs,
          define: %{"process.env.NODE_ENV" => ~s("development")},
          exports: :named,
          preserve_entry_signatures: :strict
        ]

        case OXC.bundle(entry_path, bundle_opts) do
          {:ok, result} ->
            File.write!(output_path, extract_code(result))
            {:ok, output_path}

          {:error, _} = error ->
            error
        end

      :error ->
        {:error, {:not_found, specifier}}
    end
  end

  defp prebundle_entry(specifier, module_dirs, plugins) do
    case Volt.PluginRunner.prebundle_entry(plugins, specifier) do
      {:source, filename, source} ->
        synthetic_prebundle_entry(specifier, filename, source, module_dirs)

      {:proxy, filename, _opts} = entry ->
        synthetic_prebundle_entry(
          specifier,
          filename,
          Volt.JS.PrebundleEntry.source(entry),
          module_dirs
        )

      nil ->
        package_prebundle_entry(specifier, module_dirs)
    end
  end

  defp synthetic_prebundle_entry(specifier, filename, source, module_dirs) do
    dir = Path.join([cache_dir(), "entries", encode_specifier(specifier)])
    path = Path.join(dir, filename)
    File.mkdir_p!(dir)
    File.write!(path, source)
    {:ok, path, project_root(module_dirs)}
  end

  defp package_prebundle_entry(specifier, module_dirs) do
    case resolve_package_entry(specifier, module_dirs) do
      {:ok, entry_path} -> {:ok, entry_path, package_project_root(entry_path, module_dirs)}
      :error -> :error
    end
  end

  defp package_project_root(entry_path, module_dirs) do
    entry_path
    |> Path.dirname()
    |> NPM.Resolution.PackageResolver.nearest_package()
    |> case do
      {:ok, package_dir, _package} -> Path.dirname(package_dir)
      :error -> project_root(module_dirs)
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────

  defp extract_code(result) when is_binary(result), do: result
  defp extract_code(%{code: code}), do: code

  defp resolve_package_entry(specifier, module_dirs) do
    Enum.find_value(module_dirs, :error, fn module_dir ->
      result =
        with :error <- resolve_from_node_modules(specifier, module_dir) do
          resolve_from_module_dir(specifier, module_dir)
        else
          {:ok, _path} = ok -> ok
        end

      case result do
        {:ok, _path} = ok -> ok
        :error -> nil
      end
    end)
  end

  defp resolve_from_node_modules(specifier, module_dir) do
    Volt.JS.PackageResolver.resolve(specifier, module_dir,
      extensions: Volt.JS.Extensions.resolvable()
    )
  end

  defp resolve_from_module_dir(specifier, module_dir) do
    {package_name, subpath} = split_specifier(specifier)
    package_dir = Path.join(module_dir, package_name)

    if File.dir?(package_dir) do
      NPM.Resolution.PackageResolver.resolve_entry(package_dir,
        subpath: subpath || ".",
        extensions: Volt.JS.Extensions.resolvable(),
        conditions: Volt.JS.PackageResolver.browser_conditions()
      )
    else
      :error
    end
  end

  defp split_specifier("@" <> rest = specifier) do
    case String.split(rest, "/", parts: 3) do
      [_scope, _name] -> {specifier, nil}
      [scope, name, subpath] -> {"@#{scope}/#{name}", "./#{subpath}"}
    end
  end

  defp split_specifier(specifier) do
    case String.split(specifier, "/", parts: 2) do
      [name] -> {name, nil}
      [name, subpath] -> {name, "./#{subpath}"}
    end
  end

  defp normalize_on_demand_opts(opts) do
    if Keyword.keyword?(opts) do
      {Keyword.get(opts, :plugins, []), Keyword.get(opts, :resolve_dirs, [])}
    else
      {opts, []}
    end
  end

  defp module_dirs(node_modules, resolve_dirs) do
    [node_modules | List.wrap(resolve_dirs)]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  defp project_root([module_dir | _]), do: Path.dirname(module_dir)
  defp project_root([]), do: File.cwd!()

  defp ensure_cache_dir do
    File.mkdir_p!(cache_dir())
    :ok
  end

  defp cache_path(specifier) do
    Path.join(cache_dir(), encode_specifier(specifier) <> ".js")
  end

  @doc "Encode a specifier for use in URLs (escaping @ and /)."
  def encode_specifier(specifier) do
    specifier
    |> String.replace("@", "__at__")
    |> String.replace("/", "__slash__")
  end

  @doc "Decode a URL-safe specifier back to its original form."
  def decode_specifier(encoded) do
    encoded
    |> String.replace("__slash__", "/")
    |> String.replace("__at__", "@")
  end
end
