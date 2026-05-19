defmodule Volt.CSS.AssetRewriter do
  @moduledoc """
  Parser-backed CSS asset URL rewriting for production builds.

  Uses Vize/LightningCSS to parse CSS into an AST, finds URL nodes with parser
  locations, and rewrites those source ranges through Volt's hashed asset
  pipeline.
  """

  @type rewrite_result :: {:ok, String.t()} | {:error, term()}

  @doc "Rewrite relative CSS asset URLs to hashed output URLs."
  @spec rewrite(String.t(), String.t() | nil, String.t(), keyword()) :: rewrite_result()
  def rewrite(css, source_path, outdir, opts \\ [])
  def rewrite(css, nil, _outdir, _opts), do: {:ok, css}

  def rewrite(css, source_path, outdir, opts) do
    with {:ok, %{ast: ast, errors: []}} <- Vize.CSS.parse_ast(css, filename: source_path),
         {:ok, patches} <- collect_patches(ast, css, source_path, outdir, opts) do
      {:ok, Volt.JS.Patch.apply(css, patches)}
    else
      {:ok, %{errors: errors}} when errors != [] -> {:error, {:css_parse_failed, errors}}
      {:ok, %{ast: nil}} -> {:error, :css_parse_failed}
      {:error, _} = error -> error
    end
  end

  defp collect_patches(ast, css, source_path, outdir, opts) do
    prefix = Keyword.get(opts, :prefix, "/assets")

    ast
    |> Vize.CSS.collect(fn
      %{"url" => url, "loc" => loc} when is_binary(url) and is_map(loc) ->
        {:keep, {url, loc}}

      _node ->
        :skip
    end)
    |> Enum.reduce_while({:ok, []}, fn {url, loc}, {:ok, patches} ->
      case rewrite_url(url, source_path, outdir, prefix) do
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

  defp rewrite_url(url, source_path, outdir, prefix) do
    if rewrite_candidate?(url) do
      uri = URI.parse(url)
      asset_path = Path.expand(uri.path || "", Path.dirname(source_path))

      if Volt.Assets.asset?(asset_path) and File.regular?(asset_path) do
        {:ok, filename} = Volt.Assets.copy_hashed(asset_path, outdir)
        {:ok, append_suffix(Path.join(prefix, filename), uri)}
      else
        {:ok, url}
      end
    else
      {:ok, url}
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
