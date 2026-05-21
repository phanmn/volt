defmodule Volt.JS.Transforms.AssetURLsTest do
  use ExUnit.Case, async: true

  test "rewrites relative asset URLs into URL imports" do
    source = "const logo = new URL('./logo.svg', import.meta.url).href"

    result = Volt.JS.Transforms.AssetURLs.rewrite(source, "app.ts")

    assert result =~ ~s(import __volt_asset_url_0 from "./logo.svg?url";)
    assert result =~ "new URL(__volt_asset_url_0, import.meta.url).href"
  end

  test "ignores non-asset URL constructors" do
    source = "const page = new URL('./page.ts', import.meta.url).href"

    assert Volt.JS.Transforms.AssetURLs.rewrite(source, "app.ts") == source
  end
end
