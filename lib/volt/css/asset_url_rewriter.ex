defmodule Volt.CSS.AssetURLRewriter do
  @moduledoc """
  Parser-backed CSS asset URL rewriting for production builds.

  Uses Vize/LightningCSS to parse CSS into an AST, finds URL nodes with parser
  locations, and rewrites those source ranges through Volt's asset pipeline.
  """

  @type rewrite_result :: {:ok, String.t()} | {:error, term()}
  @type rewrite_assets_result ::
          {:ok, %{code: String.t(), assets: [String.t()]}} | {:error, term()}

  @doc "Rewrite relative CSS asset URLs to hashed output URLs."
  @spec rewrite(String.t(), String.t() | nil, String.t(), keyword()) :: rewrite_result()
  def rewrite(css, source_path, outdir, opts \\ []) do
    case rewrite_with_assets(css, source_path, outdir, opts) do
      {:ok, %{code: code}} -> {:ok, code}
      {:error, _} = error -> error
    end
  end

  @doc "Rewrite relative CSS asset URLs and return emitted asset filenames."
  @spec rewrite_with_assets(String.t(), String.t() | nil, String.t(), keyword()) ::
          rewrite_assets_result()
  def rewrite_with_assets(css, source_path, outdir, opts \\ [])
  def rewrite_with_assets(css, nil, _outdir, _opts), do: {:ok, %{code: css, assets: []}}

  def rewrite_with_assets(css, source_path, outdir, opts) do
    with {:ok, %{ast: ast, errors: []}} <- Vize.CSS.parse_ast(css, filename: source_path),
         {:ok, patches, assets} <- collect_build_patches(ast, css, source_path, outdir, opts) do
      {:ok, %{code: Volt.JS.Patch.apply(css, patches), assets: Enum.reverse(assets)}}
    else
      {:ok, %{errors: errors}} when errors != [] -> {:error, {:css_parse_failed, errors}}
      {:ok, %{ast: nil}} -> {:error, :css_parse_failed}
    end
  end

  @doc "Rewrite relative CSS asset URLs to dev-server URLs without copying files."
  @spec rewrite_dev(String.t(), String.t() | nil, String.t(), String.t()) :: rewrite_result()
  def rewrite_dev(css, nil, _root, _prefix), do: {:ok, css}

  def rewrite_dev(css, source_path, root, prefix) do
    with {:ok, %{ast: ast, errors: []}} <- Vize.CSS.parse_ast(css, filename: source_path),
         {:ok, patches} <- collect_dev_patches(ast, css, source_path, root, prefix) do
      {:ok, Volt.JS.Patch.apply(css, patches)}
    else
      {:ok, %{errors: errors}} when errors != [] -> {:error, {:css_parse_failed, errors}}
      {:ok, %{ast: nil}} -> {:error, :css_parse_failed}
    end
  end

  defp collect_build_patches(ast, css, source_path, outdir, opts) do
    prefix = Keyword.get(opts, :prefix, "/assets")
    refs = css_url_refs(ast)

    Enum.reduce_while(refs, {:ok, [], [], %{}}, fn ref, acc ->
      {:cont, collect_build_patch(ref, acc, css, source_path, outdir, prefix)}
    end)
    |> case do
      {:ok, patches, assets, _emitted} -> {:ok, patches, assets}
    end
  end

  defp collect_build_patch(
         {url, loc},
         {:ok, patches, assets, emitted},
         css,
         source_path,
         outdir,
         prefix
       ) do
    case build_url(url, source_path, outdir, prefix, emitted) do
      {:ok, ^url, emitted} ->
        {:ok, patches, assets, emitted}

      {:ok, rewritten, emitted} ->
        add_build_patch(css, url, rewritten, loc, patches, assets, emitted)
    end
  end

  defp add_build_patch(css, url, rewritten, loc, patches, assets, emitted) do
    case url_patch(css, url, rewritten, loc) do
      {:ok, patch} ->
        asset = emitted_asset(rewritten)
        assets = if asset in assets, do: assets, else: [asset | assets]
        {:ok, [patch | patches], assets, emitted}

      :skip ->
        {:ok, patches, assets, emitted}
    end
  end

  defp collect_dev_patches(ast, css, source_path, root, prefix) do
    ast
    |> css_url_refs()
    |> Enum.reduce_while({:ok, []}, fn {url, loc}, {:ok, patches} ->
      case dev_url(url, source_path, root, prefix) do
        {:ok, ^url} ->
          {:cont, {:ok, patches}}

        {:ok, rewritten} ->
          case url_patch(css, url, rewritten, loc) do
            {:ok, patch} -> {:cont, {:ok, [patch | patches]}}
            :skip -> {:cont, {:ok, patches}}
          end
      end
    end)
  end

  defp css_url_refs(ast) do
    Vize.CSS.collect(ast, fn
      %{"url" => url, "loc" => loc} when is_binary(url) and is_map(loc) ->
        {:keep, {url, loc}}

      _node ->
        :skip
    end)
  end

  defp build_url(url, source_path, outdir, prefix, emitted) do
    if rewrite_candidate?(url) do
      uri = URI.parse(url)
      asset_path = Path.expand(uri.path || "", Path.dirname(source_path))

      if Volt.Assets.asset?(asset_path) and File.regular?(asset_path) do
        {filename, emitted} = emitted_filename(asset_path, outdir, emitted)
        {:ok, append_suffix(Path.join(prefix, filename), uri), emitted}
      else
        {:ok, url, emitted}
      end
    else
      {:ok, url, emitted}
    end
  end

  defp dev_url(url, source_path, root, prefix) do
    if rewrite_candidate?(url) do
      uri = URI.parse(url)
      asset_path = Path.expand(uri.path || "", Path.dirname(source_path))

      if Volt.Assets.asset?(asset_path) and File.regular?(asset_path) and
           String.starts_with?(asset_path, root) do
        relative = Path.relative_to(asset_path, root)
        {:ok, append_suffix(Path.join(prefix, relative), uri)}
      else
        {:ok, url}
      end
    else
      {:ok, url}
    end
  end

  defp emitted_filename(asset_path, outdir, emitted) do
    case Map.fetch(emitted, asset_path) do
      {:ok, filename} ->
        {filename, emitted}

      :error ->
        {:ok, filename} = Volt.Assets.copy_hashed(asset_path, outdir)
        {filename, Map.put(emitted, asset_path, filename)}
    end
  end

  defp rewrite_candidate?(url) do
    uri = URI.parse(url)

    is_binary(uri.path) and uri.path != "" and is_nil(uri.scheme) and is_nil(uri.host) and
      not String.starts_with?(url, ["/", "#", "//"])
  end

  defp url_patch(css, url, rewritten, loc) do
    start_offset = loc_offset(css, loc)
    search = binary_part(css, start_offset, byte_size(css) - start_offset)

    case :binary.match(search, url) do
      {relative_start, length} ->
        start = start_offset + relative_start
        {:ok, Volt.JS.Patch.new(start, start + length, rewritten)}

      :nomatch ->
        :skip
    end
  end

  defp loc_offset(css, %{"line" => line, "column" => column}) do
    css
    |> line_offsets()
    |> Enum.at(line - 1, 0)
    |> Kernel.+(column - 1)
  end

  defp line_offsets(css) do
    css
    |> String.split("\n")
    |> Enum.reduce({[], 0}, fn line, {offsets, offset} ->
      {[offset | offsets], offset + byte_size(line) + 1}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp emitted_asset(rewritten) do
    rewritten
    |> URI.parse()
    |> Map.fetch!(:path)
    |> Path.basename()
  end

  defp append_suffix(path, %{query: query, fragment: fragment}) do
    path
    |> append_query(query)
    |> append_fragment(fragment)
  end

  defp append_query(path, nil), do: path
  defp append_query(path, query), do: path <> "?" <> query

  defp append_fragment(path, nil), do: path
  defp append_fragment(path, fragment), do: path <> "#" <> fragment
end
