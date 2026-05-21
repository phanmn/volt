defmodule Volt.Builder.Writer do
  @moduledoc false

  def write_js(outdir, filename, code, sourcemap, opts \\ []) do
    hidden = Keyword.get(opts, :hidden, false)

    code =
      if sourcemap && !hidden do
        code <> "\n//# sourceMappingURL=#{filename}.map\n"
      else
        code
      end

    File.write!(Path.join(outdir, filename), code)

    if sourcemap do
      File.write!(Path.join(outdir, "#{filename}.map"), sourcemap)
    end
  end

  def write_css([], _outdir, _name, _hash, _bundle_opts), do: {:ok, nil}

  def write_css(css_parts, outdir, name, hash, bundle_opts) do
    with {:ok, %{code: css_code, assets: assets}} <-
           rewrite_css_parts(css_parts, outdir, bundle_opts),
         {:ok, css_code} <- compile_css(css_code, bundle_opts) do
      css_filename = hashed_name(name, css_code, ".css", hash)
      css_path = Path.join(outdir, css_filename)
      File.write!(css_path, css_code)
      {:ok, %{path: css_path, size: byte_size(css_code), assets: assets}}
    end
  end

  def build_style_entry(name, css_code, outdir, hash, source_path \\ nil, bundle_opts \\ []) do
    File.mkdir_p!(outdir)

    with {:ok, %{code: css_code, assets: assets}} <-
           rewrite_css_part({source_path, css_code}, outdir, bundle_opts),
         {:ok, css_code} <- compile_css(css_code, bundle_opts) do
      css_filename = hashed_name(name, css_code, ".css", hash)
      css_path = Path.join(outdir, css_filename)
      css_result = %{path: css_path, size: byte_size(css_code), assets: assets}

      File.write!(css_path, css_code)

      manifest = %{
        "#{name}.css" => %{
          "file" => css_filename,
          "src" => "#{name}.css",
          "assets" => css_assets(css_filename, css_result)
        }
      }

      write_manifest(outdir, manifest)

      {:ok,
       %Volt.Builder.Result{
         js: [],
         css: css_result,
         manifest: manifest
       }}
    end
  end

  defp rewrite_css_parts(css_parts, outdir, bundle_opts) do
    css_parts
    |> Enum.reduce_while({:ok, [], []}, fn css_part, {:ok, code_parts, assets} ->
      case rewrite_css_part(css_part, outdir, bundle_opts) do
        {:ok, %{code: code, assets: part_assets}} ->
          {:cont, {:ok, [code | code_parts], merge_assets(assets, part_assets)}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, code_parts, assets} ->
        {:ok, %{code: code_parts |> Enum.reverse() |> Enum.join("\n"), assets: assets}}

      {:error, _} = error ->
        error
    end
  end

  defp rewrite_css_part({source_path, css}, outdir, bundle_opts) do
    Volt.CSS.AssetURLRewriter.rewrite_with_assets(css, source_path, outdir,
      prefix: Keyword.get(bundle_opts, :asset_url_prefix, "/assets")
    )
  end

  defp rewrite_css_part(css, _outdir, _bundle_opts), do: {:ok, %{code: css, assets: []}}

  defp compile_css(css_code, bundle_opts) do
    case Vize.CSS.compile(css_code, minify: bundle_opts[:minify] || false) do
      {:ok, %{errors: [_ | _] = errors}} -> {:error, {:css_compile_failed, errors}}
      {:ok, %{code: code}} -> {:ok, code}
    end
  end

  def write_manifest(outdir, manifest) do
    File.write!(Path.join(outdir, "manifest.json"), :json.encode(manifest))
  end

  def build_manifest(name, js_filename, css_result) do
    manifest = %{
      "#{name}.js" => %{
        "file" => js_filename,
        "src" => "#{name}.js"
      }
    }

    add_css_to_manifest(manifest, name, css_result)
  end

  def add_css_to_manifest(manifest, _name, nil), do: manifest

  def add_css_to_manifest(manifest, name, css_result) do
    css_filename = Path.basename(css_result.path)

    manifest
    |> put_in(["#{name}.js", "css"], [css_filename])
    |> Map.put("#{name}.css", %{
      "file" => css_filename,
      "src" => "#{name}.css",
      "assets" => css_assets(css_filename, css_result)
    })
  end

  def hashed_name(name, content, ext, true) do
    "#{name}-#{Volt.Format.content_hash(content)}#{ext}"
  end

  def hashed_name(name, _content, ext, false), do: "#{name}#{ext}"

  defp css_assets(css_filename, css_result) do
    [css_filename | Map.get(css_result, :assets, [])]
  end

  defp merge_assets(left, right) do
    Enum.reduce(right, left, fn asset, acc ->
      if asset in acc, do: acc, else: [asset | acc]
    end)
  end
end
