defmodule Volt.CSS.AssetRewriterTest do
  use ExUnit.Case, async: true

  @fixture_dir Path.expand("../fixtures/css_asset_rewriter", __DIR__)

  setup do
    File.rm_rf!(@fixture_dir)
    File.mkdir_p!(Path.join(@fixture_dir, "src/images"))
    File.mkdir_p!(Path.join(@fixture_dir, "dist"))
    File.write!(Path.join(@fixture_dir, "src/images/logo.svg"), "<svg></svg>")

    on_exit(fn -> File.rm_rf!(@fixture_dir) end)
    :ok
  end

  test "rewrites relative CSS url assets to output URLs" do
    css = ~S|.logo { background: url("./images/logo.svg") }|

    result =
      Volt.CSS.AssetRewriter.rewrite(
        css,
        Path.join(@fixture_dir, "src/app.css"),
        Path.join(@fixture_dir, "dist")
      )

    assert result =~ ~S|url("/assets/logo-|
    refute result =~ "./images/logo.svg"
    assert ["logo-" <> _] = File.ls!(Path.join(@fixture_dir, "dist"))
  end

  test "inlines relative CSS imports with per-file asset provenance" do
    File.mkdir_p!(Path.join(@fixture_dir, "src/components/icons"))
    File.write!(Path.join(@fixture_dir, "src/components/icons/logo.svg"), "<svg></svg>")

    File.write!(
      Path.join(@fixture_dir, "src/components/button.css"),
      ".btn { background: url('./icons/logo.svg') }"
    )

    File.write!(Path.join(@fixture_dir, "src/app.css"), "@import './components/button.css';")

    result =
      Volt.CSS.AssetRewriter.rewrite_file(
        Path.join(@fixture_dir, "src/app.css"),
        Path.join(@fixture_dir, "dist")
      )

    assert result =~ "/assets/logo-"
    refute result =~ "./icons/logo.svg"
    assert Enum.any?(File.ls!(Path.join(@fixture_dir, "dist")), &String.starts_with?(&1, "logo-"))
  end

  test "leaves external and absolute URLs unchanged" do
    css =
      ~S|.a { background: url("/logo.svg") } .b { background: url(data:image/svg+xml;base64,abc) }|

    result =
      Volt.CSS.AssetRewriter.rewrite(
        css,
        Path.join(@fixture_dir, "src/app.css"),
        @fixture_dir
      )

    assert result =~ "/logo.svg"
    assert result =~ "data:image/svg+xml;base64,abc"
  end
end
