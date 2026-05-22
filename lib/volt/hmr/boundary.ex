defmodule Volt.HMR.Boundary do
  @moduledoc """
  Detects HMR boundaries from the dev module graph and source ASTs.

  When a file changes, Volt first checks `Volt.HMR.ModuleGraph` for served
  importers and self-accepting modules. If the file has not entered the dev
  module graph yet, boundary lookup falls back to `Volt.HMR.ImportGraph` raw
  specifiers. If no self-accepting boundary is found, the client performs a full
  reload.
  """

  @doc """
  Check if a module's source code contains `import.meta.hot.accept()`.
  """
  @spec self_accepting?(String.t()) :: boolean()
  def self_accepting?(source) do
    case OXC.parse(source, "hmr-boundary.js") do
      {:ok, ast} -> ast_self_accepting?(ast)
      {:error, _} -> false
    end
  end

  @doc """
  Find the HMR boundary for a changed file.

  Walks upward through the module graph from `changed_path`. Returns
  `{:ok, boundary_path}` if a self-accepting module is found, or
  `:full_reload` if the change bubbles up to the root without finding
  a boundary.

  The `read_source` function is called with an absolute path and should
  return the module's source code for boundary detection.
  """
  @spec find_boundary(String.t(), (String.t() -> String.t() | nil)) ::
          {:ok, String.t()} | :full_reload
  def find_boundary(changed_path, read_source) do
    source = read_source.(changed_path)

    cond do
      source && self_accepting?(source) ->
        {:ok, changed_path}

      graph_boundary = find_graph_boundary(changed_path, read_source) ->
        graph_boundary

      true ->
        walk_up(changed_path, read_source, MapSet.new([changed_path]))
    end
  end

  defp ast_self_accepting?(ast) do
    {_ast, found?} =
      OXC.postwalk(ast, false, fn
        node, false -> {node, accept_call?(node)}
        node, true -> {node, true}
      end)

    found?
  end

  defp accept_call?(node) when is_map(node) do
    result =
      Volt.JS.AST.call_member_arguments(node, {:meta_property, "import", "meta", "hot"}, "accept")

    case result do
      {:ok, []} ->
        true

      {:ok, [%{type: type} | _]}
      when type in [:arrow_function_expression, :function_expression] ->
        true

      _ ->
        false
    end
  end

  defp accept_call?(_node), do: false

  defp find_graph_boundary(changed_path, read_source) do
    changed_path
    |> Volt.HMR.ModuleGraph.get_by_file()
    |> case do
      [] ->
        nil

      nodes ->
        find_graph_boundary_in_nodes(nodes, read_source, MapSet.new(Enum.map(nodes, & &1.id)))
    end
  end

  defp find_graph_boundary_in_nodes(nodes, read_source, visited) do
    Enum.find_value(nodes, :full_reload, fn node ->
      cond do
        graph_self_accepting?(node, read_source) ->
          {:ok, node.file}

        MapSet.size(node.importers) == 0 ->
          nil

        true ->
          node.importers
          |> Enum.flat_map(&List.wrap(Volt.HMR.ModuleGraph.get_by_id(&1)))
          |> Enum.reject(&MapSet.member?(visited, &1.id))
          |> find_graph_boundary_in_nodes(read_source, MapSet.union(visited, node.importers))
          |> case do
            :full_reload -> nil
            found -> found
          end
      end
    end)
  end

  defp graph_self_accepting?(node, read_source) do
    case read_source.(node.file) do
      source when is_binary(source) -> self_accepting?(source)
      _ -> node.self_accepting
    end
  end

  defp walk_up(path, read_source, visited) do
    case find_importers(path) do
      [] -> :full_reload
      parents -> find_boundary_in_parents(parents, read_source, visited)
    end
  end

  defp find_boundary_in_parents(parents, read_source, visited) do
    Enum.find_value(parents, :full_reload, fn parent ->
      if MapSet.member?(visited, parent) do
        nil
      else
        visit_parent(parent, read_source, MapSet.put(visited, parent))
      end
    end)
  end

  defp visit_parent(parent, read_source, visited) do
    source = read_source.(parent)

    if source != nil and self_accepting?(source) do
      {:ok, parent}
    else
      case walk_up(parent, read_source, visited) do
        {:ok, _} = found -> found
        :full_reload -> nil
      end
    end
  end

  defp find_importers(path) do
    basename = Path.basename(path)
    rootname = Path.rootname(basename)

    Volt.HMR.ImportGraph.dependents_matching(fn specifier ->
      spec_base = specifier |> String.split("/") |> List.last()

      spec_base == basename or
        spec_base == rootname or
        Path.rootname(spec_base) == rootname
    end)
  end
end
