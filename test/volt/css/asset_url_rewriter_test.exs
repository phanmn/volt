defmodule Volt.CSS.AssetURLRewriterTest do
  use ExUnit.Case, async: true

  @fixture_dir Path.expand("../fixtures/css_asset_rewriter", __DIR__)
  @outdir Path.join(@fixture_dir, "dist")

  setup do
    File.rm_rf!(@fixture_dir)
    File.mkdir_p!(Path.join(@fixture_dir, "src/icons"))
    File.mkdir_p!(@outdir)

    on_exit(fn -> File.rm_rf!(@fixture_dir) end)

    :ok
  end

  test "rewrites relative url nodes through hashed assets" do
    File.write!(Path.join(@fixture_dir, "src/icons/logo.svg"), "<svg></svg>")
    source_path = Path.join(@fixture_dir, "src/app.css")

    {:ok, css} =
      Volt.CSS.AssetURLRewriter.rewrite(
        ".logo { background: url('./icons/logo.svg') }",
        source_path,
        @outdir
      )

    assert css =~ ~r/url\(['"]\/assets\/logo-[a-f0-9]{8}\.svg['"]\)/
    assert [asset] = Path.wildcard(Path.join(@outdir, "logo-*.svg"))
    assert File.read!(asset) == "<svg></svg>"
  end

  test "rewrites image-set url nodes and preserves query and fragment suffixes" do
    File.write!(Path.join(@fixture_dir, "src/one.png"), "one")
    File.write!(Path.join(@fixture_dir, "src/two.png"), "two")
    source_path = Path.join(@fixture_dir, "src/app.css")

    {:ok, css} =
      Volt.CSS.AssetURLRewriter.rewrite(
        ".hero { background-image: image-set(url('./one.png?v=1#x') 1x, url('./two.png') 2x) }",
        source_path,
        @outdir
      )

    assert css =~ ~r/\/assets\/one-[a-f0-9]{8}\.png\?v=1#x/
    assert css =~ ~r/\/assets\/two-[a-f0-9]{8}\.png/
  end

  test "leaves external, absolute, data, and unknown URLs unchanged" do
    source_path = Path.join(@fixture_dir, "src/app.css")

    {:ok, css} =
      Volt.CSS.AssetURLRewriter.rewrite(
        ".a{background:url('https://example.com/a.png')} .b{background:url('/logo.svg')} .c{background:url('data:image/svg+xml;base64,abc')} .d{background:url('./missing.svg')}",
        source_path,
        @outdir
      )

    assert css =~ "https://example.com/a.png"
    assert css =~ "/logo.svg"
    assert css =~ "data:image/svg+xml;base64,abc"
    assert css =~ "./missing.svg"
  end
end
