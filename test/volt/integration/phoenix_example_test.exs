defmodule Volt.Integration.PhoenixExampleTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  import Plug.Test
  import Plug.Conn

  @example_dir Path.join(File.cwd!(), "examples/vanilla")
  @assets_root Path.join(@example_dir, "assets")

  describe "dev server" do
    setup do
      Volt.Cache.clear()
      :ok
    end

    test "serves entry module with HMR preamble and rewritten imports" do
      conn = call_dev_server("/assets/js/app.ts")

      assert conn.status == 200
      assert content_type(conn) =~ "javascript"
      assert conn.resp_body =~ "createHotContext"
      assert conn.resp_body =~ "/@vendor/phoenix.js"
      assert conn.resp_body =~ "/@vendor/phoenix_html.js"
      assert conn.resp_body =~ "/@vendor/phoenix_live_view.js"
      refute conn.resp_body =~ ~s(from 'phoenix')
      refute conn.resp_body =~ ~s(from 'phoenix_html')
      refute conn.resp_body =~ ~s(from 'phoenix_live_view')
    end

    test "serves hook modules with HMR preamble" do
      conn = call_dev_server("/assets/js/hooks/clock.ts")

      assert conn.status == 200
      assert conn.resp_body =~ "createHotContext"
      assert conn.resp_body =~ "clearInterval"
    end

    test "rewrites relative imports to absolute dev paths" do
      conn = call_dev_server("/assets/js/app.ts")

      assert conn.resp_body =~ "/assets/js/hooks/clock"
      assert conn.resp_body =~ "/assets/js/hooks/env-mode"
    end

    test "serves vendor phoenix module" do
      conn = call_dev_server("/@vendor/phoenix.js")

      assert conn.status == 200
      assert content_type(conn) =~ "javascript"
      assert conn.resp_body =~ "Socket"
      assert conn.resp_body =~ "Channel"
    end

    test "serves vendor phoenix_live_view module" do
      conn = call_dev_server("/@vendor/phoenix_live_view.js")

      assert conn.status == 200
      assert content_type(conn) =~ "javascript"
      assert conn.resp_body =~ "LiveSocket"
    end

    test "serves vendor phoenix_html module" do
      conn = call_dev_server("/@vendor/phoenix_html.js")

      assert conn.status == 200
      assert content_type(conn) =~ "javascript"
    end

    test "serves JSON modules" do
      conn = call_dev_server("/assets/js/config.json")

      assert conn.status == 200
      assert conn.resp_body =~ "export default"
    end

    test "serves static assets" do
      conn = call_dev_server("/assets/images/volt.svg")

      assert conn.status == 200
      assert content_type(conn) =~ "svg"
    end
  end

  defp call_dev_server(path) do
    opts = Volt.DevServer.init(root: @assets_root, prefix: "/assets")
    conn(:get, path) |> Volt.DevServer.call(opts)
  end

  defp content_type(conn) do
    get_resp_header(conn, "content-type") |> hd()
  end
end

defmodule Volt.Integration.PhoenixExampleBuildTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  @example_dir Path.join(File.cwd!(), "examples/vanilla")
  @outdir Path.join(@example_dir, "priv/static/assets")

  setup_all do
    File.rm_rf!(Path.join(@outdir, "js"))
    File.rm_rf!(Path.join(@outdir, "css"))

    {output, status} =
      System.cmd("mix", ["volt.build", "--tailwind", "--no-hash", "--no-minify"],
        cd: @example_dir,
        stderr_to_stdout: true
      )

    %{build_output: output, build_status: status}
  end

  test "exits successfully", %{build_status: status} do
    assert status == 0
  end

  test "produces JS bundle with Phoenix deps bundled in", %{build_status: 0} do
    js = File.read!(Path.join(@outdir, "js/app.js"))

    assert js =~ "LiveSocket"
    assert js =~ "phoenix"
    assert js =~ "csrfToken"
    refute js =~ ~s(import "phoenix")
    refute js =~ ~s(import "phoenix_html")
  end

  test "includes glob imports in bundle", %{build_status: 0} do
    js = File.read!(Path.join(@outdir, "js/app.js"))

    assert js =~ "About"
    assert js =~ "Built with Volt"
    assert js =~ "Home"
  end

  test "produces valid manifest", %{build_status: 0} do
    manifest = @outdir |> Path.join("js/manifest.json") |> File.read!() |> Jason.decode!()

    assert Map.has_key?(manifest, "app.js")
    assert manifest["app.js"]["file"] == "app.js"
  end

  test "produces Tailwind CSS with utility classes from heex templates", %{build_status: 0} do
    css = File.read!(Path.join(@outdir, "css/app.css"))

    assert css =~ "rounded-2xl"
    assert css =~ "bg-amber-600"
    assert css =~ "font-semibold"
  end

  test "generates sourcemap", %{build_status: 0} do
    map = @outdir |> Path.join("js/app.js.map") |> File.read!() |> Jason.decode!()

    assert map["version"] == 3
  end
end
