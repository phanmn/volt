defmodule Volt.JS.ImportExtractor do
  @moduledoc false

  @type import_type :: :static | :dynamic
  @type result :: %{imports: [{import_type(), String.t()}], workers: [String.t()]}

  @spec extract_typed(String.t(), String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def extract_typed(source, filename, opts \\ []) do
    if needs_postwalk?(source) do
      extract_typed_slow(source, filename, opts)
    else
      case OXC.collect_imports(source, filename) do
        {:ok, imports} ->
          typed = Enum.map(imports, &{&1.type, &1.specifier})
          {:ok, %{imports: typed, workers: []}}

        {:error, _} = error ->
          error
      end
    end
  end

  defp needs_postwalk?(source) do
    String.contains?(source, "require(") or String.contains?(source, "new Worker") or
      String.contains?(source, "new SharedWorker")
  end

  defp extract_typed_slow(source, filename, opts) do
    ignore_type_only? = Keyword.get(opts, :ignore_type_only, false)

    case OXC.parse(source, filename) do
      {:ok, ast} ->
        {_ast, acc} =
          OXC.postwalk(ast, %{imports: [], workers: []}, fn
            %{type: :import_declaration, source: %{value: spec}} = node, acc ->
              add_import(
                node,
                acc,
                {:static, spec},
                ignore_type_only? and type_only_import?(node)
              )

            %{type: :export_named_declaration, source: %{value: spec}} = node, acc
            when is_binary(spec) ->
              add_import(
                node,
                acc,
                {:static, spec},
                ignore_type_only? and type_only_export?(node)
              )

            %{type: :export_all_declaration, source: %{value: spec}} = node, acc ->
              {node, update_in(acc.imports, &[{:static, spec} | &1])}

            %{type: :import_expression, source: %{type: :literal, value: spec}} = node, acc
            when is_binary(spec) ->
              {node, update_in(acc.imports, &[{:dynamic, spec} | &1])}

            node, acc ->
              maybe_extract_require(node, acc)
          end)

        {:ok, %{imports: Enum.reverse(acc.imports), workers: Enum.reverse(acc.workers)}}

      {:error, _} ->
        case OXC.imports(source, filename) do
          {:ok, specs} -> {:ok, %{imports: Enum.map(specs, &{:static, &1}), workers: []}}
          error -> error
        end
    end
  end

  defp maybe_extract_require(node, acc) do
    case Volt.JS.AST.call_arguments(node, "require") do
      {:ok, [source | _]} ->
        add_require_import(node, acc, Volt.JS.AST.string_literal_span(source))

      _ ->
        maybe_extract_worker(node, acc)
    end
  end

  defp add_require_import(node, acc, {:ok, spec, _start, _end}),
    do: {node, update_in(acc.imports, &[{:static, spec} | &1])}

  defp add_require_import(node, acc, nil), do: maybe_extract_worker(node, acc)

  defp maybe_extract_worker(node, acc) do
    case Volt.JS.AST.new_arguments(node, ["Worker", "SharedWorker"]) do
      {:ok, _worker_type, [first_arg | _]} ->
        case Volt.JS.WorkerRewriter.extract_specifier(first_arg) do
          {:ok, spec, _start, _end} -> {node, update_in(acc.workers, &[spec | &1])}
          nil -> {node, acc}
        end

      _ ->
        {node, acc}
    end
  end

  defp add_import(node, acc, _import, true), do: {node, acc}
  defp add_import(node, acc, import, false), do: {node, update_in(acc.imports, &[import | &1])}

  defp type_only_import?(%{importKind: "type"}), do: true

  defp type_only_import?(%{specifiers: specifiers}) when is_list(specifiers) do
    specifiers != [] and Enum.all?(specifiers, &(Map.get(&1, :importKind) == "type"))
  end

  defp type_only_import?(_node), do: false

  defp type_only_export?(%{exportKind: "type"}), do: true
  defp type_only_export?(_node), do: false
end
