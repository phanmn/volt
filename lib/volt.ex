defmodule Volt do
  @moduledoc """
  Elixir-native frontend build tool.

  Provides a dev server with hot module replacement (HMR) and production
  builds for JavaScript, TypeScript, Vue SFCs, and CSS — powered by
  OXC and Vize Rust NIFs. No Node.js required at runtime.

  ## Setup

  Add Volt to your Phoenix endpoint as a Plug:

      plug Volt.DevServer,
        root: "assets/src",
        target: :es2020

  Or use the Mix tasks:

      mix volt.build       # Production build
  """

  @doc """
  Returns the browser path for the configured Volt entry.

  In development this points at the source module served by `Volt.DevServer`.
  In production it reads `manifest.json` and returns the built asset path.
  """
  def entry_path(endpoint, overrides \\ []) do
    build = Volt.Config.build(overrides)
    server = Volt.Config.server(overrides)
    entry = build.entry |> List.wrap() |> hd()

    if code_reloader?(endpoint) do
      server.prefix
      |> Path.join(Path.relative_to(entry, build.root))
      |> ensure_leading_slash()
    else
      built_entry_path(endpoint, build, server.prefix, overrides)
    end
  end

  defp built_entry_path(endpoint, build, prefix, overrides) do
    name = Keyword.get(overrides, :name) || entry_name(build.entry)
    manifest_key = "#{name}.js"

    case find_manifest_entry(endpoint, build.outdir, prefix, manifest_key) do
      {:ok, file, manifest_prefix} ->
        endpoint
        |> static_path(Path.join(manifest_prefix, file))
        |> ensure_leading_slash()

      :error ->
        endpoint
        |> static_path(Path.join([prefix, "js", manifest_key]))
        |> ensure_leading_slash()
    end
  end

  defp find_manifest_entry(endpoint, outdir, prefix, manifest_key) do
    root_outdir = resolve_outdir(endpoint, outdir)

    [
      {root_outdir, prefix},
      {Path.join(root_outdir, "js"), Path.join(prefix, "js")}
    ]
    |> Enum.find_value(:error, fn {manifest_dir, manifest_prefix} ->
      manifest_path = Path.join(manifest_dir, "manifest.json")

      with {:ok, json} <- File.read(manifest_path),
           manifest when is_map(manifest) <- :json.decode(json),
           %{"file" => file} <- Map.get(manifest, manifest_key) do
        {:ok, file, manifest_prefix}
      else
        _ -> nil
      end
    end)
  end

  defp resolve_outdir(endpoint, outdir) do
    outdir = to_string(outdir)

    cond do
      Path.type(outdir) == :absolute ->
        outdir

      otp_app = otp_app(endpoint) ->
        resolve_app_path(otp_app, outdir)

      true ->
        Path.expand(outdir)
    end
  end

  defp resolve_app_path(otp_app, "priv/" <> _ = outdir) do
    Application.app_dir(otp_app, outdir)
  rescue
    _ -> Path.expand(outdir)
  end

  defp resolve_app_path(_otp_app, outdir), do: Path.expand(outdir)

  defp static_path(endpoint, path) do
    endpoint.static_path(path)
  rescue
    UndefinedFunctionError -> path
  end

  defp otp_app(endpoint) do
    endpoint.config(:otp_app)
  rescue
    _ -> nil
  end

  defp entry_name(entry) do
    entry
    |> List.wrap()
    |> hd()
    |> Path.basename()
    |> Path.rootname()
  end

  defp code_reloader?(endpoint) do
    endpoint.config(:code_reloader)
  rescue
    _ -> false
  end

  defp ensure_leading_slash("/" <> _ = path), do: path
  defp ensure_leading_slash(path), do: "/" <> path
end
