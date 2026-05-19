defmodule Volt.JS.DynamicImportVars do
  @moduledoc """
  Rewrites simple variable dynamic imports into import maps.
  """

  @doc """
  Transform relative template-literal dynamic imports.
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
         true <- relative_pattern?(pattern) do
      {:ok,
       %{
         start: node.start,
         end: node.end,
         index: nil,
         template: String.slice(source, source_node.start, source_node.end - source_node.start),
         pattern: pattern
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
        replacement = "__volt_dynamic_import_#{rewrite.index}(#{rewrite.template})"
        Volt.JS.Patch.new(rewrite.start, rewrite.end, replacement)
      end)

    IO.iodata_to_binary([helpers, "\n", Volt.JS.Patch.apply(source, patches)])
  end

  defp helper(rewrite) do
    modules = "__volt_dynamic_import_modules_#{rewrite.index}"
    importer = "__volt_dynamic_import_importer_#{rewrite.index}"
    helper = "__volt_dynamic_import_#{rewrite.index}"

    [
      "const ",
      modules,
      " = import.meta.glob(",
      Jason.encode!(rewrite.pattern),
      ");\nconst ",
      helper,
      " = (path) => {\n  const ",
      importer,
      " = ",
      modules,
      "[path];\n  if (",
      importer,
      ") return ",
      importer,
      "();\n  return Promise.reject(new Error(\"Unknown variable dynamic import: \" + path));\n};"
    ]
  end
end
