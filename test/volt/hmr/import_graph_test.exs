defmodule Volt.HMR.ImportGraphTest do
  use ExUnit.Case, async: false

  setup do
    Volt.HMR.ImportGraph.clear()
    :ok
  end

  test "tracks imports for a file" do
    Volt.HMR.ImportGraph.update("/src/App.vue", ["vue", "./utils"])
    assert Volt.HMR.ImportGraph.imports_of("/src/App.vue") == ["vue", "./utils"]
  end

  test "finds dependents of a specifier" do
    Volt.HMR.ImportGraph.update("/src/App.vue", ["./utils", "vue"])
    Volt.HMR.ImportGraph.update("/src/Page.vue", ["./utils"])
    Volt.HMR.ImportGraph.update("/src/main.ts", ["vue"])

    dependents = Volt.HMR.ImportGraph.dependents("./utils")
    assert "/src/App.vue" in dependents
    assert "/src/Page.vue" in dependents
    refute "/src/main.ts" in dependents
  end

  test "update replaces previous imports" do
    Volt.HMR.ImportGraph.update("/src/App.vue", ["vue", "./old"])
    Volt.HMR.ImportGraph.update("/src/App.vue", ["vue", "./new"])
    assert Volt.HMR.ImportGraph.imports_of("/src/App.vue") == ["vue", "./new"]
  end

  test "update_from_compiled extracts imports" do
    compiled = """
    import './setup'
    const pages = { './pages/home.ts': () => import('./pages/home.ts') }
    """

    Volt.HMR.ImportGraph.update_from_compiled("/src/routes.ts", compiled)

    assert "./setup" in Volt.HMR.ImportGraph.imports_of("/src/routes.ts")
  end

  test "remove deletes a file from the graph" do
    Volt.HMR.ImportGraph.update("/src/App.vue", ["vue"])
    Volt.HMR.ImportGraph.remove("/src/App.vue")
    assert Volt.HMR.ImportGraph.imports_of("/src/App.vue") == []
  end
end
