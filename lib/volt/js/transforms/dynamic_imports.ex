defmodule Volt.JS.Transforms.DynamicImports do
  @moduledoc """
  Rewrites relative template-literal dynamic imports into import maps.

  JavaScript bundlers cannot statically follow `import(`./pages/${name}.ts`)`
  without first expanding the possible files. Volt rewrites those imports through
  `import.meta.glob()` so the normal glob transform can add the matching modules
  to the dev and production graphs.

  The transform intentionally supports the same conservative shape Vite supports
  best: relative template literals with at least one expression. Bare package
  imports and absolute URLs are left untouched.

  Helper code is generated from OXC templates and spliced into parsed source so
  the emitted JavaScript remains parser-validated.
  """

  @doc """
  Transforms relative template-literal dynamic imports in `source`.

  Returns the original source unchanged when parsing fails or no supported
  dynamic import is found.
  """
  @spec transform(String.t(), String.t()) :: String.t()
  def transform(source, filename \\ "dynamic-import-vars.ts") do
    case OXC.parse(source, filename) do
      {:ok, ast} ->
        rewrites = collect_rewrites(ast, source)
        if rewrites == [], do: source, else: apply_rewrites(source, rewrites)

      {:error, _} ->
        source
    end
  end

  defp collect_rewrites(ast, source) do
    {_ast, rewrites} =
      OXC.postwalk(ast, [], fn node, acc ->
        case dynamic_import_rewrite(node, source, length(acc)) do
          {:ok, rewrite} -> {node, [rewrite | acc]}
          :skip -> {node, acc}
        end
      end)

    rewrites
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map(fn {rewrite, index} -> %{rewrite | index: index} end)
  end

  defp dynamic_import_rewrite(
         %{
           type: :import_expression,
           options: nil,
           source: %{type: :template_literal} = source_node
         } = node,
         source,
         _index
       ) do
    with {:ok, pattern} <- glob_pattern(source_node),
         {path_pattern, query} <- Volt.URL.split_query(pattern),
         true <- relative_pattern?(path_pattern) do
      {:ok,
       %Volt.JS.Transforms.DynamicImports.Replacement{
         start: node.start,
         end: node.end,
         template: String.slice(source, source_node.start, source_node.end - source_node.start),
         pattern: path_pattern,
         query: query
       }}
    else
      _ -> :skip
    end
  end

  defp dynamic_import_rewrite(_node, _source, _index), do: :skip

  defp glob_pattern(%{quasis: quasis, expressions: expressions}) when expressions != [] do
    pattern =
      quasis
      |> Enum.map(fn quasi ->
        get_in(quasi, [:value, :cooked]) || get_in(quasi, [:value, :raw]) || ""
      end)
      |> Enum.intersperse("*")
      |> IO.iodata_to_binary()

    {:ok, pattern}
  end

  defp glob_pattern(_node), do: :skip

  defp relative_pattern?("./" <> _), do: true
  defp relative_pattern?("../" <> _), do: true
  defp relative_pattern?(_pattern), do: false

  defp apply_rewrites(source, rewrites) do
    helpers =
      rewrites
      |> Enum.map(&helper/1)
      |> Enum.intersperse("\n")

    patches =
      Enum.map(rewrites, fn rewrite ->
        replacement = [
          "__volt_dynamic_import_",
          Integer.to_string(rewrite.index),
          "(",
          rewrite.template,
          ")"
        ]

        Volt.JS.Patch.new(rewrite.start, rewrite.end, replacement)
      end)

    IO.iodata_to_binary([helpers, "\n", Volt.JS.Patch.apply(source, patches)])
  end

  defp helper(rewrite) do
    template =
      if rewrite.query == "" do
        "const $modules = import.meta.glob($pattern);\n$helper"
      else
        "const $modules = import.meta.glob($pattern, { query: $query });\n$helper"
      end

    template
    |> OXC.parse!("dynamic-import-helper.js")
    |> OXC.bind(
      modules: modules_identifier(rewrite),
      pattern: {:literal, rewrite.pattern},
      query: {:literal, "?" <> rewrite.query}
    )
    |> OXC.splice(:helper, dynamic_import_function_ast(rewrite))
    |> OXC.codegen!()
    |> String.trim()
  end

  defp dynamic_import_function_ast(rewrite) do
    OXC.parse!(
      "const $helper = (path) => {\n  const $importer = $modules[$lookup];\n  if ($importer) return $importer();\n  return Promise.reject(new Error(\"Unknown variable dynamic import: \" + path));\n};",
      "dynamic-import-function.js"
    )
    |> OXC.bind(
      helper: helper_identifier(rewrite),
      importer: importer_identifier(rewrite),
      modules: modules_identifier(rewrite),
      lookup: lookup_expression(rewrite)
    )
    |> Map.fetch!(:body)
    |> hd()
  end

  defp modules_identifier(rewrite), do: "__volt_dynamic_import_modules_#{rewrite.index}"
  defp importer_identifier(rewrite), do: "__volt_dynamic_import_importer_#{rewrite.index}"
  defp helper_identifier(rewrite), do: "__volt_dynamic_import_#{rewrite.index}"

  defp lookup_expression(%{query: ""}), do: {:expr, "path"}
  defp lookup_expression(%{query: _query}), do: {:expr, "path.split(\"?\")[0]"}
end
