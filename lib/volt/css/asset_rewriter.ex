defmodule Volt.CSS.AssetRewriter do
  @moduledoc """
  Rewrites relative CSS `url(...)` asset references to build output URLs.

  Production CSS needs the same asset treatment as JavaScript imports: files are
  copied to the output directory with content hashes and CSS references are
  rewritten to public `/assets/...` URLs. Absolute paths, data URLs, fragments,
  and remote URLs are preserved.
  """

  @asset_prefix "/assets"

  @doc """
  Copies relative CSS URL assets to `outdir` and rewrites references.

  `source_path` is the CSS file that owns the URLs, so relative paths are
  resolved from its directory.
  """
  @spec rewrite(String.t(), String.t(), String.t()) :: String.t()
  def rewrite(css, source_path, outdir) do
    do_rewrite(css, String.downcase(css), source_path, outdir, 0, [])
  end

  defp do_rewrite(css, lower, source_path, outdir, offset, acc) do
    case :binary.match(lower, "url(", scope: {offset, byte_size(css) - offset}) do
      {start, 4} ->
        case parse_url(css, start + 4) do
          {:ok, finish, specifier} ->
            replacement = rewrite_url(specifier, source_path, outdir)

            do_rewrite(css, lower, source_path, outdir, finish + 1, [
              acc,
              binary_part(css, offset, start - offset),
              replacement
            ])

          :skip ->
            do_rewrite(css, lower, source_path, outdir, start + 4, [
              acc,
              binary_part(css, offset, start + 4 - offset)
            ])
        end

      :nomatch ->
        IO.iodata_to_binary([acc, binary_part(css, offset, byte_size(css) - offset)])
    end
  end

  defp parse_url(css, offset) do
    offset = skip_spaces(css, offset)

    cond do
      offset >= byte_size(css) ->
        :skip

      binary_part(css, offset, 1) in ["\"", "'"] ->
        parse_quoted_url(css, offset, binary_part(css, offset, 1))

      true ->
        parse_unquoted_url(css, offset)
    end
  end

  defp parse_quoted_url(css, offset, quote) do
    value_start = offset + 1

    with {:ok, quote_end} <- find_quote(css, value_start, quote),
         close <- skip_spaces(css, quote_end + 1),
         true <- close < byte_size(css),
         ")" <- binary_part(css, close, 1) do
      {:ok, close, binary_part(css, value_start, quote_end - value_start)}
    else
      _ -> :skip
    end
  end

  defp parse_unquoted_url(css, offset) do
    case find_closing_paren(css, offset) do
      {:ok, finish} ->
        value =
          css
          |> binary_part(offset, finish - offset)
          |> String.trim()

        {:ok, finish, value}

      :error ->
        :skip
    end
  end

  defp find_quote(css, offset, quote) do
    cond do
      offset >= byte_size(css) ->
        :error

      binary_part(css, offset, 1) == "\\" ->
        find_quote(css, min(offset + 2, byte_size(css)), quote)

      binary_part(css, offset, 1) == quote ->
        {:ok, offset}

      true ->
        find_quote(css, offset + 1, quote)
    end
  end

  defp find_closing_paren(css, offset) do
    cond do
      offset >= byte_size(css) ->
        :error

      binary_part(css, offset, 1) == ")" ->
        {:ok, offset}

      true ->
        find_closing_paren(css, offset + 1)
    end
  end

  defp skip_spaces(css, offset) do
    if offset < byte_size(css) and binary_part(css, offset, 1) in [" ", "\n", "\r", "\t", "\f"] do
      skip_spaces(css, offset + 1)
    else
      offset
    end
  end

  defp rewrite_url(specifier, source_path, outdir) do
    with false <- external_url?(specifier),
         {path, suffix} <- split_suffix(specifier),
         true <- Volt.Assets.asset?(path),
         asset_path = Path.expand(path, Path.dirname(source_path)),
         true <- File.regular?(asset_path),
         {:ok, filename} <- Volt.Assets.copy_hashed(asset_path, outdir) do
      "url(\"#{@asset_prefix}/#{filename}#{suffix}\")"
    else
      _ -> "url(#{specifier})"
    end
  end

  defp external_url?(""), do: true
  defp external_url?("/" <> _), do: true
  defp external_url?("#" <> _), do: true

  defp external_url?(specifier),
    do: String.contains?(specifier, ":") or String.starts_with?(specifier, "//")

  defp split_suffix(specifier) do
    query_index = index_of(specifier, "?")
    hash_index = index_of(specifier, "#")

    split_at =
      [query_index, hash_index]
      |> Enum.reject(&is_nil/1)
      |> Enum.min(fn -> nil end)

    if split_at do
      {binary_part(specifier, 0, split_at),
       binary_part(specifier, split_at, byte_size(specifier) - split_at)}
    else
      {specifier, ""}
    end
  end

  defp index_of(string, pattern) do
    case :binary.match(string, pattern) do
      {index, _length} -> index
      :nomatch -> nil
    end
  end
end
