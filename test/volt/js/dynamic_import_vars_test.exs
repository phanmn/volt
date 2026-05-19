defmodule Volt.JS.DynamicImportVarsTest do
  use ExUnit.Case, async: true

  test "rewrites relative template dynamic imports through import.meta.glob" do
    source = "const mod = await import(`./pages/${name}.ts`)"

    result = Volt.JS.DynamicImportVars.transform(source, "app.ts")

    assert result =~ ~S|const __volt_dynamic_import_modules_0 = import.meta.glob("./pages/*.ts");|
    assert result =~ "__volt_dynamic_import_0(`./pages/${name}.ts`)"
    refute result =~ "await import(`./pages/${name}.ts`)"
  end

  test "ignores bare package dynamic imports" do
    source = "const mod = await import(`pkg/${name}.js`)"

    assert Volt.JS.DynamicImportVars.transform(source, "app.ts") == source
  end
end
