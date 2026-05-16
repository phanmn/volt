defmodule Volt.PipelineTest do
  use ExUnit.Case, async: true

  describe "compile/3 with TypeScript" do
    test "strips types and returns sourcemap" do
      {:ok, result} = Volt.Pipeline.compile("app.ts", "const x: number = 42")
      assert result.code =~ "const x = 42"
      assert is_binary(result.sourcemap)
      assert result.css == nil
      assert result.hashes == nil
    end

    test "compiles JSX" do
      {:ok, result} = Volt.Pipeline.compile("app.tsx", "<div />")
      assert result.code =~ "jsx"
    end

    test "applies target downleveling" do
      {:ok, result} = Volt.Pipeline.compile("app.js", "const x = a ?? b", target: :es2019)
      refute result.code =~ "??"
    end

    test "injects import.meta.env defines" do
      {:ok, result} =
        Volt.Pipeline.compile("app.ts", "console.log(import.meta.env.MODE, import.meta.env.DEV)",
          define: %{
            "import.meta.env.MODE" => ~s("development"),
            "import.meta.env.DEV" => "true"
          }
        )

      assert result.code =~ ~s(import.meta.env = { "DEV": true, "MODE": "development" };)
      assert result.code =~ "console.log(import.meta.env.MODE, import.meta.env.DEV)"
    end

    test "supports runtime access to injected import.meta.env" do
      source = "const key = 'MODE'; console.log(import.meta.env[key], import.meta.env)"

      {:ok, result} =
        Volt.Pipeline.compile("app.ts", source,
          define: %{"import.meta.env.MODE" => ~s("development")}
        )

      assert result.code =~ ~s("MODE": "development")
      assert result.code =~ "import.meta.env[key]"
      assert result.code =~ "console.log(import.meta.env[key], import.meta.env)"
    end

    test "supports destructuring import.meta.env" do
      {:ok, result} =
        Volt.Pipeline.compile("app.ts", "const { MODE } = import.meta.env; console.log(MODE)",
          define: %{"import.meta.env.MODE" => ~s("development")}
        )

      assert result.code =~ ~s("MODE": "development")
      assert result.code =~ "const { MODE } = import.meta.env"
    end

    test "supports optional access to import.meta.env" do
      {:ok, result} =
        Volt.Pipeline.compile("app.ts", "console.log(import.meta?.env?.MODE)",
          define: %{"import.meta.env.MODE" => ~s("development")}
        )

      assert result.code =~ ~s("MODE": "development")
      assert result.code =~ "import.meta?.env?.MODE"
    end

    test "does not inject import.meta.env for string literals or unrelated import.meta properties" do
      source = "console.log('import.meta.env', import.meta.url)"

      {:ok, result} =
        Volt.Pipeline.compile("app.ts", source,
          define: %{"import.meta.env.MODE" => ~s("development")}
        )

      refute result.code =~ "import.meta.env ="
      assert result.code =~ "import.meta.url"
      assert result.code =~ ~s("import.meta.env")
    end

    test "leaves non import.meta.env defines unchanged" do
      source = "function f(process) { return process.env.NODE_ENV }"

      {:ok, result} =
        Volt.Pipeline.compile("app.js", source,
          define: %{"process.env.NODE_ENV" => ~s("development")}
        )

      assert result.code =~ "process.env.NODE_ENV"
    end
  end

  describe "compile/3 with Vue SFC" do
    test "compiles a simple SFC" do
      source = """
      <template><div>{{ msg }}</div></template>
      <script setup>const msg = 'hi'</script>
      """

      {:ok, result} = Volt.Pipeline.compile("App.vue", source)
      assert result.code =~ "msg"
      assert result.hashes.template != nil
    end

    test "returns CSS from scoped styles" do
      source = """
      <template><div class="box">hi</div></template>
      <style scoped>.box { color: red }</style>
      """

      {:ok, result} = Volt.Pipeline.compile("App.vue", source)
      assert is_binary(result.css)
    end
  end

  describe "compile/3 with CSS" do
    test "passes through CSS" do
      {:ok, result} = Volt.Pipeline.compile("app.css", ".foo { color: red }")
      assert result.code =~ "color"
    end

    test "minifies CSS" do
      {:ok, result} = Volt.Pipeline.compile("app.css", ".foo {\n  color: red;\n}", minify: true)
      refute result.code =~ "\n"
    end

    test "inlines @import from disk" do
      dir = Path.expand("fixtures/css_import", __DIR__)
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "reset.css"), "* { margin: 0 }")
      File.write!(Path.join(dir, "app.css"), "@import \"./reset.css\";\n.app { color: red }")

      on_exit(fn -> File.rm_rf!(dir) end)

      path = Path.join(dir, "app.css")
      {:ok, result} = Volt.Pipeline.compile(path, File.read!(path))
      assert result.code =~ "margin"
      assert result.code =~ "color"
      refute result.code =~ "@import"
    end
  end

  describe "compile/3 with import rewriting" do
    test "rewrites imports when rewrite_import is provided" do
      source = "import { ref } from 'vue'\nconst x = ref(0)"

      {:ok, result} =
        Volt.Pipeline.compile("app.ts", source,
          rewrite_import: fn
            "vue" -> {:rewrite, "/@vendor/vue.js"}
            _ -> :keep
          end
        )

      assert result.code =~ "/@vendor/vue.js"
      refute result.code =~ "'vue'"
    end

    test "skips rewriting when no rewrite_import given" do
      {:ok, result} = Volt.Pipeline.compile("app.ts", "import { ref } from 'vue'\nref(0)")
      assert result.code =~ "vue"
    end
  end

  describe "compile/3 with JSON" do
    test "wraps JSON as ES module" do
      {:ok, result} = Volt.Pipeline.compile("data.json", ~s({"key":"value"}))
      assert result.code =~ "export default"
      assert result.code =~ ~s("key")
    end
  end

  describe "compile/3 with CSS Modules" do
    test "compiles .module.css to JS + scoped CSS" do
      {:ok, result} = Volt.Pipeline.compile("btn.module.css", ".btn { color: red }")
      assert result.code =~ "export default"
      assert result.css =~ "btn"
      assert result.css =~ "color"
    end
  end

  describe "compile/3 errors" do
    test "returns error for unsupported extensions" do
      {:error, {:unsupported, ".xyz"}} = Volt.Pipeline.compile("data.xyz", "binary")
    end

    test "returns error for invalid TypeScript" do
      {:error, errors} = Volt.Pipeline.compile("bad.ts", "const = ;")
      assert is_list(errors)
    end
  end
end
