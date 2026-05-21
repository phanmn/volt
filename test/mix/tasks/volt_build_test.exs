defmodule Mix.Tasks.Volt.BuildTest do
  use ExUnit.Case, async: false

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    Mix.Task.reenable("volt.build")

    tmp_dir =
      Path.join(System.tmp_dir!(), "volt-build-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(tmp_dir, "src"))

    on_exit(fn ->
      Mix.shell(previous_shell)
      Mix.Task.reenable("volt.build")
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "--no-tree-shaking preserves unused exports", %{tmp_dir: tmp_dir} do
    entry = Path.join(tmp_dir, "src/app.js")
    outdir = Path.join(tmp_dir, "dist")

    File.write!(Path.join(tmp_dir, "src/lib.js"), """
    export function used() { return 'used' }
    export function unused() { return 'unused' }
    """)

    File.write!(entry, """
    import { used } from './lib.js'
    console.log(used())
    """)

    Mix.Tasks.Volt.Build.run([
      "--entry",
      entry,
      "--outdir",
      outdir,
      "--no-hash",
      "--no-minify",
      "--no-tailwind",
      "--format",
      "iife",
      "--sourcemap",
      "false",
      "--no-tree-shaking"
    ])

    js_path = Path.join([outdir, "js", "app.js"])
    assert File.read!(js_path) =~ "unused"
  end

  test "--asset-url-prefix sets production asset URLs", %{tmp_dir: tmp_dir} do
    entry = Path.join(tmp_dir, "src/app.js")
    outdir = Path.join(tmp_dir, "dist")

    File.write!(Path.join(tmp_dir, "src/logo.svg"), "<svg></svg>")

    File.write!(entry, """
    import logo from './logo.svg?url'
    console.log(logo)
    """)

    Mix.Tasks.Volt.Build.run([
      "--entry",
      entry,
      "--outdir",
      outdir,
      "--asset-url-prefix",
      "/cdn/assets",
      "--no-hash",
      "--no-minify",
      "--no-tailwind",
      "--format",
      "iife",
      "--sourcemap",
      "false"
    ])

    js_path = Path.join([outdir, "js", "app.js"])
    assert File.read!(js_path) =~ ~r(/cdn/assets/logo-[a-f0-9]{8}\.svg)
  end

  test "--sourcemap false disables production sourcemaps", %{tmp_dir: tmp_dir} do
    entry = Path.join(tmp_dir, "src/app.js")
    outdir = Path.join(tmp_dir, "dist")

    File.write!(entry, "console.log('app')")

    Mix.Tasks.Volt.Build.run([
      "--entry",
      entry,
      "--outdir",
      outdir,
      "--no-hash",
      "--no-minify",
      "--no-tailwind",
      "--format",
      "iife",
      "--sourcemap",
      "false"
    ])

    js_path = Path.join([outdir, "js", "app.js"])
    assert File.regular?(js_path)
    refute File.exists?(js_path <> ".map")
  end
end
