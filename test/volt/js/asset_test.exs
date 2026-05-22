defmodule Volt.JS.AssetTest do
  use ExUnit.Case, async: true

  test "reads TypeScript assets from priv/ts" do
    code = Volt.JS.Asset.read!("dev/hmr-client.ts")
    assert code =~ "const proto"
  end

  test "rewrites type-checkable support imports to runtime client URL" do
    code = Volt.JS.Asset.compiled_template!("dev/hmr-preamble.ts", mod_url: "/assets/app.ts")

    assert code =~ ~s(from "/@volt/client.js")
    refute code =~ "./hmr-client"
  end
end
