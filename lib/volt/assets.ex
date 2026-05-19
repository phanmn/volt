defmodule Volt.Assets do
  @moduledoc """
  Static asset handling — images, fonts, SVGs, and other non-code files.

  Small assets (below the inline threshold) are inlined as base64 data URIs.
  Larger assets are copied with content-hashed filenames.

  ## Import patterns

      // Inlined as data URI when small enough
      import icon from './icon.svg'
      // icon = "data:image/svg+xml;base64,..."

      // Forced public URL
      import photo from './photo.jpg?url'
      // photo = "/assets/photo-a1b2c3d4.jpg"

      // Raw file contents
      import text from './message.txt?raw'

  JavaScript `new URL("./asset.ext", import.meta.url)` references and CSS
  `url("./asset.ext")` references are also routed through this asset pipeline in
  production builds.
  """

  @default_inline_limit 4096

  @mime_types %{
    ".svg" => "image/svg+xml",
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".gif" => "image/gif",
    ".webp" => "image/webp",
    ".avif" => "image/avif",
    ".ico" => "image/x-icon",
    ".woff" => "font/woff",
    ".woff2" => "font/woff2",
    ".ttf" => "font/ttf",
    ".eot" => "application/vnd.ms-fontobject",
    ".otf" => "font/otf",
    ".mp4" => "video/mp4",
    ".webm" => "video/webm",
    ".ogg" => "audio/ogg",
    ".mp3" => "audio/mpeg",
    ".wav" => "audio/wav",
    ".pdf" => "application/pdf",
    ".wasm" => "application/wasm",
    ".txt" => "text/plain"
  }

  @doc "Check if a path is a known asset type."
  @spec asset?(String.t()) :: boolean()
  def asset?(path) do
    Map.has_key?(@mime_types, Path.extname(path))
  end

  @doc """
  Generate a JS module that exports asset content or a URL.

  ## Options

    * `:raw` — export the file contents as a string
    * `:url` — force a public URL instead of inlining
    * `:inline` — force a data URI
    * `:no_inline` — force a public URL even for small assets
    * `:inline_limit` — byte threshold for default inlining (default: 4096)
    * `:prefix` — URL prefix for referenced assets (default: `"/assets"`)
    * `:outdir` — output directory for copied assets (production only)
    * `:url_path` — dev-server URL to export when no `:outdir` is provided
  """
  @spec to_js_module(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def to_js_module(path, opts \\ []) do
    cond do
      Keyword.get(opts, :raw, false) ->
        raw_asset(path)

      Keyword.get(opts, :url, false) ->
        reference_asset(path, opts)

      Keyword.get(opts, :inline, false) ->
        inline_asset(path)

      Keyword.get(opts, :no_inline, false) ->
        reference_asset(path, opts)

      true ->
        limit = Keyword.get(opts, :inline_limit, @default_inline_limit)

        case File.stat(path) do
          {:ok, %{size: size}} when size <= limit ->
            inline_asset(path)

          {:ok, _stat} ->
            reference_asset(path, opts)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Copy an asset to the output directory with a content-hashed filename.

  Returns `{:ok, hashed_filename}`.
  """
  @spec copy_hashed(String.t(), String.t()) :: {:ok, String.t()}
  def copy_hashed(source_path, outdir) do
    content = File.read!(source_path)
    ext = Path.extname(source_path)
    name = Path.basename(source_path, ext)
    hash = Volt.Format.content_hash(content)
    filename = "#{name}-#{hash}#{ext}"
    dest = Path.join(outdir, filename)

    File.mkdir_p!(outdir)
    File.write!(dest, content)

    {:ok, filename}
  end

  @doc "Get MIME type for a file extension."
  @spec mime_type(String.t()) :: String.t()
  def mime_type(path) do
    Map.get(@mime_types, Path.extname(path), "application/octet-stream")
  end

  defp raw_asset(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, "export default #{Jason.encode!(content)};\n"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp inline_asset(path) do
    content = File.read!(path)
    mime = mime_type(path)
    encoded = Base.encode64(content)
    js = ~s(export default "data:#{mime};base64,#{encoded}";\n)
    {:ok, js}
  end

  defp reference_asset(path, opts) do
    prefix = Keyword.get(opts, :prefix, "/assets")

    case Keyword.get(opts, :outdir) do
      nil ->
        url = Keyword.get(opts, :url_path) || Path.join(prefix, Path.basename(path))
        {:ok, ~s(export default "#{url}";\n)}

      outdir ->
        {:ok, filename} = copy_hashed(path, outdir)
        {:ok, ~s(export default "#{prefix}/#{filename}";\n)}
    end
  end
end
