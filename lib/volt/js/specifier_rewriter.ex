defmodule Volt.JS.SpecifierRewriter do
  @moduledoc false

  @type rewrite_result :: :skip | {:ok, String.t() | nil, String.t()} | {:error, term()}
  @type rewrite_fun :: (String.t(), String.t(), term() -> rewrite_result())

  @spec rewrite(String.t(), String.t(), term(), rewrite_fun()) ::
          {:ok, String.t(), [String.t()]} | {:error, term()}
  def rewrite(source, importer, context, rewrite_fun) do
    case OXC.parse(source, Path.basename(importer)) do
      {:ok, ast} ->
        {patches, resolved_paths} = collect_patches(ast, importer, context, rewrite_fun)
        {:ok, OXC.patch_string(source, patches), resolved_paths}

      {:error, errors} ->
        {:error, {:parse_error, importer, errors}}
    end
  catch
    {:error, _} = error -> error
  end

  defp collect_patches(ast, importer, context, rewrite_fun) do
    {_ast, {patches, paths}} =
      OXC.postwalk(ast, {[], []}, fn
        %{type: type, source: %{value: specifier, start: start_pos, end: end_pos}}, acc
        when type in [:import_declaration, :export_all_declaration, :export_named_declaration] ->
          {nil,
           accumulate_patch(specifier, start_pos, end_pos, importer, context, rewrite_fun, acc)}

        %{
          type: :import_expression,
          source: %{type: :literal, value: specifier, start: start_pos, end: end_pos}
        } = node,
        acc
        when is_binary(specifier) ->
          {node,
           accumulate_patch(specifier, start_pos, end_pos, importer, context, rewrite_fun, acc)}

        %{
          type: :call_expression,
          callee: %{type: :identifier, name: "require"},
          arguments: [%{value: specifier, start: start_pos, end: end_pos}]
        } = node,
        acc
        when is_binary(specifier) ->
          {node,
           accumulate_patch(specifier, start_pos, end_pos, importer, context, rewrite_fun, acc)}

        node, acc ->
          {node, acc}
      end)

    {Enum.reverse(patches), Enum.reverse(paths)}
  end

  defp accumulate_patch(
         specifier,
         start_pos,
         end_pos,
         importer,
         context,
         rewrite_fun,
         {patches, paths}
       ) do
    case rewrite_fun.(specifier, importer, context) do
      :skip ->
        {patches, paths}

      {:ok, nil, resolved_path} ->
        {patches, [resolved_path | paths]}

      {:ok, replacement, resolved_path} ->
        patch = %{start: start_pos, end: end_pos, change: inspect(replacement)}
        {[patch | patches], [resolved_path | paths]}

      {:error, _reason} ->
        {patches, paths}
    end
  end
end
