defmodule Volt.URLTest do
  use ExUnit.Case, async: true

  describe "join/2" do
    test "joins path prefixes" do
      assert Volt.URL.join("/assets", "app.js") == "/assets/app.js"
      assert Volt.URL.join("/assets/", "/app.js") == "/assets/app.js"
    end

    test "joins absolute URL prefixes" do
      assert Volt.URL.join("https://cdn.example.com/assets/", "app.js") ==
               "https://cdn.example.com/assets/app.js"
    end

    test "supports empty prefixes for relative URLs" do
      assert Volt.URL.join("", "app.js") == "app.js"
    end
  end

  describe "split_query/1" do
    test "uses URI parsing to separate the path and query" do
      assert Volt.URL.split_query("./logo.svg?url") == {"./logo.svg", "url"}
      assert Volt.URL.split_query("/assets/app.js?raw#hash") == {"/assets/app.js", "raw"}
    end
  end

  describe "append_query/2 and append_fragment/2" do
    test "adds query and fragment with URI semantics" do
      assert Volt.URL.append_query("/assets/app.js", "import") == "/assets/app.js?import"
      assert Volt.URL.append_query("/assets/app.js?raw", "url") == "/assets/app.js?raw&url"

      assert "/assets/app.js"
             |> Volt.URL.append_query("v=1")
             |> Volt.URL.append_fragment("hash") == "/assets/app.js?v=1#hash"
    end

    test "preserves absolute URL components" do
      assert "https://cdn.example.com/assets/app.js"
             |> Volt.URL.append_query("v=1")
             |> Volt.URL.append_fragment("hash") ==
               "https://cdn.example.com/assets/app.js?v=1#hash"
    end
  end
end
