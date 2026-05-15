defmodule VoltTest do
  use ExUnit.Case, async: true
  doctest Volt

  defmodule DevEndpoint do
    def config(:code_reloader), do: true
  end

  defmodule ProdEndpoint do
    def config(:code_reloader), do: false
  end

  defmodule StaticEndpoint do
    def config(:code_reloader), do: false
    def static_path("/assets/js/app.js"), do: "/assets/js/app-digested.js?vsn=d"
    def static_path(path), do: path
  end

  test "entry_path points at source entry in development" do
    assert Volt.entry_path(DevEndpoint,
             entry: "assets/js/app.tsx",
             root: "assets",
             prefix: "/assets"
           ) == "/assets/js/app.tsx"
  end

  test "entry_path reads production manifest" do
    outdir = tmp_dir("manifest")
    File.mkdir_p!(outdir)
    File.write!(Path.join(outdir, "manifest.json"), ~s({"app.js":{"file":"app-deadbeef.js"}}))

    assert Volt.entry_path(ProdEndpoint,
             entry: "assets/js/app.ts",
             outdir: outdir,
             prefix: "/assets"
           ) == "/assets/app-deadbeef.js"
  end

  test "entry_path reads production manifest from build task js directory" do
    outdir = tmp_dir("manifest-js")
    js_outdir = Path.join(outdir, "js")
    File.mkdir_p!(js_outdir)
    File.write!(Path.join(js_outdir, "manifest.json"), ~s({"app.js":{"file":"app-cafebabe.js"}}))

    assert Volt.entry_path(ProdEndpoint,
             entry: "assets/js/app.ts",
             outdir: outdir,
             prefix: "/assets"
           ) == "/assets/js/app-cafebabe.js"
  end

  test "entry_path prefers root manifest for backwards compatibility" do
    outdir = tmp_dir("manifest-precedence")
    js_outdir = Path.join(outdir, "js")
    File.mkdir_p!(js_outdir)
    File.write!(Path.join(outdir, "manifest.json"), ~s({"app.js":{"file":"app-root.js"}}))
    File.write!(Path.join(js_outdir, "manifest.json"), ~s({"app.js":{"file":"app-js.js"}}))

    assert Volt.entry_path(ProdEndpoint,
             entry: "assets/js/app.ts",
             outdir: outdir,
             prefix: "/assets"
           ) == "/assets/app-root.js"
  end

  test "entry_path falls back to build task js path when manifest is missing" do
    outdir = tmp_dir("manifest-missing")

    assert Volt.entry_path(ProdEndpoint,
             entry: "assets/js/app.ts",
             outdir: outdir,
             prefix: "/assets"
           ) == "/assets/js/app.js"
  end

  test "entry_path uses endpoint static_path for Phoenix digest lookup" do
    outdir = tmp_dir("manifest-static-path")
    js_outdir = Path.join(outdir, "js")
    File.mkdir_p!(js_outdir)
    File.write!(Path.join(js_outdir, "manifest.json"), ~s({"app.js":{"file":"app.js"}}))

    assert Volt.entry_path(StaticEndpoint,
             entry: "assets/js/app.ts",
             outdir: outdir,
             prefix: "/assets"
           ) == "/assets/js/app-digested.js?vsn=d"
  end

  defp tmp_dir(name) do
    Path.join([System.tmp_dir!(), "volt-test-#{System.unique_integer([:positive])}", name])
  end
end
