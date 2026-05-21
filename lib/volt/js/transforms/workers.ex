defmodule Volt.JS.Transforms.Workers do
  @moduledoc "Finds and rewrites `new Worker(new URL(..., import.meta.url))` module specifiers."

  alias Volt.JS.AST

  @spec rewrite(String.t(), String.t(), (String.t() -> {:rewrite, String.t()} | :keep)) ::
          {:ok, String.t()} | {:error, term()}
  def rewrite(source, filename, rewrite_fn) do
    case OXC.parse(source, filename) do
      {:ok, ast} ->
        patches = collect_worker_patches(ast, rewrite_fn)
        if patches == [], do: {:ok, source}, else: {:ok, Volt.JS.Patch.apply(source, patches)}

      {:error, _} = error ->
        error
    end
  end

  @doc false
  @spec extract_specifier(map()) :: {:ok, String.t(), non_neg_integer(), non_neg_integer()} | nil
  def extract_specifier(node) do
    case AST.new_arguments(node, ["URL"]) do
      {:ok, _name, [source_node, meta_url | _]} ->
        if worker_url_base?(meta_url) do
          AST.string_literal_span(source_node)
        end

      _ ->
        nil
    end
  end

  defp worker_url_base?(node) do
    AST.import_meta_property?(node, "url") or generated_import_meta_url?(node)
  end

  defp generated_import_meta_url?(%{
         type: :member_expression,
         computed: false,
         property: %{type: :identifier, name: "url"},
         object: %{type: :object_expression, properties: []}
       }),
       do: true

  defp generated_import_meta_url?(_node), do: false

  defp collect_worker_patches(ast, rewrite_fn) do
    {_ast, patches} =
      OXC.postwalk(ast, [], fn
        node, patches ->
          case AST.new_arguments(node, ["Worker", "SharedWorker"]) do
            {:ok, _worker_type, [first_arg | _]} ->
              patch_worker_specifier(node, first_arg, rewrite_fn, patches)

            _ ->
              {node, patches}
          end
      end)

    patches
  end

  defp patch_worker_specifier(node, first_arg, rewrite_fn, patches) do
    case extract_specifier(first_arg) do
      {:ok, specifier, s, e} ->
        case rewrite_fn.(specifier) do
          {:rewrite, new} -> {node, [Volt.JS.Patch.new(s, e, AST.string_literal(new)) | patches]}
          :keep -> {node, patches}
        end

      nil ->
        {node, patches}
    end
  end
end
