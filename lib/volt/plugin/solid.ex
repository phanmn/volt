defmodule Volt.Plugin.Solid do
  @moduledoc """
  Solid JSX/TSX support for Volt.

  Solid JSX requires the Solid compiler rather than a generic JSX runtime
  transform. This plugin runs `babel-preset-solid` through Volt's JavaScript
  runtime and leaves normal module resolution to Volt. Add `Volt.Plugin.Solid`
  to `config :volt, :plugins` when using Solid TSX, since `.jsx` and `.tsx`
  files are also used by React and generic JSX builds.
  """

  @behaviour Volt.Plugin

  @runtime_packages %{
    "@babel/standalone" => "^7.0.0",
    "babel-preset-solid" => "^1.9.0"
  }

  @runtime_name __MODULE__.Runtime
  @jsx_exts ~w(.jsx .tsx)
  @web_imports ~w(
    Aliases
    Assets
    ChildProperties
    DOMElements
    DelegatedEvents
    Dynamic
    ErrorBoundary
    For
    Hydration
    HydrationScript
    Index
    Match
    NoHydration
    Portal
    Properties
    RequestContext
    SVGElements
    SVGNamespace
    Show
    Suspense
    SuspenseList
    Switch
    addEventListener
    assign
    classList
    className
    clearDelegatedEvents
    createComponent
    createDynamic
    delegateEvents
    dynamicProperty
    effect
    escape
    generateHydrationScript
    getAssets
    getHydrationKey
    getNextElement
    getNextMarker
    getNextMatch
    getOwner
    getPropAlias
    getRequestEvent
    hydrate
    innerHTML
    insert
    isDev
    isServer
    memo
    mergeProps
    render
    renderToStream
    renderToString
    renderToStringAsync
    resolveSSRNode
    runHydrationEvents
    setAttribute
    setAttributeNS
    setBoolAttribute
    setProperty
    setStyleProperty
    spread
    ssr
    ssrAttribute
    ssrClassList
    ssrElement
    ssrHydrationKey
    ssrSpread
    ssrStyle
    style
    template
    untrack
    use
    useAssets
  )

  @impl true
  def name, do: "solid"

  @impl true
  def compile(path, source, opts), do: compile(path, source, opts, [])

  def compile(path, source, opts, plugin_opts) do
    filename = compile_filename(path, opts)

    if solid_file?(filename) do
      do_compile(source, filename, opts, plugin_opts)
    end
  end

  @impl true
  def extract_imports(path, source, opts), do: extract_imports(path, source, opts, [])

  def extract_imports(path, source, opts, _plugin_opts) do
    filename = compile_filename(path, opts)

    if solid_file?(filename) do
      with {:ok, %{imports: imports} = result} <- extract_typed_imports(source, filename) do
        {:ok, %{result | imports: add_compiler_imports(imports)}}
      end
    end
  end

  @impl true
  def prebundle_alias("solid-js/web"), do: "solid-js"
  def prebundle_alias(_specifier), do: nil

  @impl true
  def prebundle_entry("solid-js") do
    web_exports = Enum.map(@web_imports, &{&1, &1})

    {:proxy, "solid-js.js",
     exports: [
       %{all_from: "solid-js"},
       %{named_from: "solid-js/web", names: web_exports}
     ]}
  end

  def prebundle_entry(_specifier), do: nil

  def runtime_packages, do: @runtime_packages

  defp do_compile(source, filename, opts, plugin_opts) do
    runtime =
      Volt.JS.Runtime.ensure!(
        name: @runtime_name,
        packages: @runtime_packages,
        apis: [:browser, :node],
        entry: {:volt_asset, "solid-runtime.ts"},
        bundle: true,
        max_stack_size: 32 * 1024 * 1024
      )

    compile_options = compile_options(filename, opts, plugin_opts)

    case Volt.JS.Runtime.call(runtime, "compileSolid", [source, compile_options]) do
      {:ok, %{"code" => code, "map" => map}} ->
        with {:ok, code, downlevelled?} <- maybe_downlevel(code, filename, opts) do
          {:ok,
           %{
             code: code,
             sourcemap: encode_sourcemap(map, downlevelled?),
             css: nil,
             hashes: %{template: nil, style: nil, script: hash(source)}
           }}
        end

      {:ok, other} ->
        {:error, {:unexpected_solid_result, other}}

      {:error, _} = error ->
        error
    end
  end

  defp compile_options(filename, opts, plugin_opts) do
    solid_options =
      %{
        "generate" => option(opts, plugin_opts, :generate, "dom"),
        "hydratable" => option(opts, plugin_opts, :hydratable, false),
        "dev" => option(opts, plugin_opts, :dev, false)
      }
      |> Map.merge(stringify_keys(Keyword.get(plugin_opts, :solid_options, %{})))
      |> Map.merge(stringify_keys(Keyword.get(opts, :solid_options, %{})))

    options = %{
      "filename" => filename,
      "typescript" => Path.extname(filename) in ~w(.ts .tsx .mts),
      "sourcemap" => Keyword.get(opts, :sourcemap, true),
      "solidOptions" => solid_options
    }

    case stringify_keys(Keyword.get(plugin_opts, :typescript_options, %{})) do
      map when map_size(map) == 0 -> options
      map -> Map.put(options, "typescriptOptions", map)
    end
  end

  defp maybe_downlevel(code, filename, opts) do
    case Keyword.get(opts, :target) do
      nil ->
        {:ok, code, false}

      "" ->
        {:ok, code, false}

      target ->
        case OXC.transform(code, js_filename(filename),
               target: to_string(target),
               sourcemap: false
             ) do
          {:ok, transformed} when is_binary(transformed) ->
            {:ok, transformed, transformed != code}

          {:ok, %{code: transformed}} ->
            {:ok, transformed, transformed != code}

          {:error, _} = error ->
            error
        end
    end
  end

  defp js_filename(filename), do: Path.rootname(filename) <> ".js"

  defp compile_filename(path, opts) do
    path
    |> Path.basename()
    |> Volt.JS.Extensions.apply_loader(Keyword.get(opts, :loaders, %{}))
  end

  defp solid_file?(filename), do: Path.extname(filename) in @jsx_exts

  defp add_compiler_imports(imports) do
    imports
    |> Enum.concat([{:static, "solid-js/web"}])
    |> Enum.uniq()
  end

  defp extract_typed_imports(source, filename) do
    Volt.JS.ImportExtractor.extract_typed(source, filename, ignore_type_only: true)
  end

  defp option(opts, plugin_opts, key, default) do
    Keyword.get(opts, key, Keyword.get(plugin_opts, key, default))
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp encode_sourcemap(_map, true), do: nil
  defp encode_sourcemap(nil, false), do: nil
  defp encode_sourcemap(map, false) when is_map(map), do: Jason.encode!(map)
  defp encode_sourcemap(value, false) when is_binary(value), do: value

  defp hash(nil), do: nil
  defp hash(""), do: nil
  defp hash(value), do: :erlang.phash2(value) |> Integer.to_string(16)
end
