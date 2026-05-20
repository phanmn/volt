defmodule Volt.CSS.AssetURLRewriter do
  @moduledoc """
  Parser-backed CSS asset URL rewriting for production builds.

  Uses Vize/LightningCSS to parse CSS into an AST, rewrites URL nodes, and
  prints the transformed AST back to CSS.
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
    with {:parse, {:ok, %{ast: ast, errors: []}}} <-
           {:parse, Vize.CSS.parse_ast(css, filename: source_path)},
         {ast, assets} <- rewrite_build_ast(ast, source_path, outdir, opts),
         {:print, {:ok, %{code: code, errors: []}}} <- {:print, Vize.CSS.print_ast(ast)} do
      {:ok, %{code: code, assets: assets}}
    else
      {:parse, {:ok, %{errors: errors}}} when errors != [] ->
        {:error, {:css_parse_failed, errors}}

      {:parse, {:ok, %{ast: nil}}} ->
        {:error, :css_parse_failed}

      {:print, {:ok, %{errors: errors}}} when errors != [] ->
        {:error, {:css_print_failed, errors}}
    end
  end

  @doc "Rewrite relative CSS asset URLs to dev-server URLs without copying files."
  @spec rewrite_dev(String.t(), String.t() | nil, String.t(), String.t()) :: rewrite_result()
  def rewrite_dev(css, nil, _root, _prefix), do: {:ok, css}

  def rewrite_dev(css, source_path, root, prefix) do
    with {:parse, {:ok, %{ast: ast, errors: []}}} <-
           {:parse, Vize.CSS.parse_ast(css, filename: source_path)},
         ast <- rewrite_dev_ast(ast, source_path, root, prefix),
         {:print, {:ok, %{code: code, errors: []}}} <- {:print, Vize.CSS.print_ast(ast)} do
      {:ok, code}
    else
      {:parse, {:ok, %{errors: errors}}} when errors != [] ->
        {:error, {:css_parse_failed, errors}}

      {:parse, {:ok, %{ast: nil}}} ->
        {:error, :css_parse_failed}

      {:print, {:ok, %{errors: errors}}} when errors != [] ->
        {:error, {:css_print_failed, errors}}
    end
  end

  defp rewrite_build_ast(ast, source_path, outdir, opts) do
    prefix = Keyword.get(opts, :prefix, "/assets")

    {ast, {assets, _emitted}} =
      Vize.CSS.postwalk(ast, {[], %{}}, fn
        %{"url" => url} = node, {assets, emitted} when is_binary(url) ->
          case build_url(url, source_path, outdir, prefix, emitted) do
            {:ok, ^url, emitted} ->
              {node, {assets, emitted}}

            {:ok, rewritten, emitted} ->
              asset = emitted_asset(rewritten)
              assets = if asset in assets, do: assets, else: [asset | assets]
              {Map.put(node, "url", rewritten), {assets, emitted}}
          end

        node, acc ->
          {node, acc}
      end)

    {ast, Enum.reverse(assets)}
  end

  defp rewrite_dev_ast(ast, source_path, root, prefix) do
    Vize.CSS.postwalk(ast, fn
      %{"url" => url} = node when is_binary(url) ->
        case dev_url(url, source_path, root, prefix) do
          {:ok, ^url} -> node
          {:ok, rewritten} -> Map.put(node, "url", rewritten)
        end

      node ->
        node
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
