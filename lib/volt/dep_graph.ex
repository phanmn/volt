defmodule Volt.DepGraph do
  @moduledoc """
  ETS-backed legacy module import graph.

  Tracks raw import specifiers for compatibility fallback while the dev server
  uses `Volt.HMR.ModuleGraph` for resolved HMR propagation. `import.meta.glob()`
  ownership lives in `Volt.HMR.GlobGraph`.
  """

  @table :volt_dep_graph

  @doc "Create the dependency graph ETS table. Called once from Application.start/2."
  @spec create_table :: :ok
  def create_table do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    :ok
  end

  @doc "Update the imports for a file path."
  @spec update(String.t(), [String.t()], [String.t()]) :: :ok
  def update(path, imports, globs \\ []) do
    if globs != [], do: Volt.HMR.GlobGraph.update(path, globs)
    :ets.insert(@table, {path, imports})
    :ok
  end

  @doc "Update imports from compiled code and glob ownership from source."
  @spec update_from_source(String.t(), String.t(), String.t()) :: :ok
  def update_from_source(path, source, compiled_code) do
    imports =
      case OXC.imports(compiled_code, Path.basename(path)) do
        {:ok, imports} -> imports
        _ -> []
      end

    Volt.HMR.GlobGraph.update_from_source(path, source)
    update(path, imports)
  end

  @doc "Get the imports for a file path."
  @spec imports_of(String.t()) :: [String.t()]
  def imports_of(path) do
    case :ets.lookup(@table, path) do
      [{_, imports}] -> imports
      [{_, imports, _globs}] -> imports
      [] -> []
    end
  end

  @doc """
  Find all files that import the given specifier.

  Used by HMR to propagate changes upward through the dependency tree.
  """
  @spec dependents(String.t()) :: [String.t()]
  def dependents(specifier) do
    :ets.foldl(
      fn
        {path, imports}, acc ->
          if specifier in imports, do: [path | acc], else: acc

        {path, imports, _globs}, acc ->
          if specifier in imports, do: [path | acc], else: acc
      end,
      [],
      @table
    )
  end

  @doc """
  Find all files that import a specifier matching the given predicate.

  The predicate receives each import specifier and should return `true`
  if it matches the file being searched for.
  """
  @spec dependents_matching((String.t() -> boolean())) :: [String.t()]
  def dependents_matching(predicate) do
    :ets.foldl(
      fn
        {path, imports}, acc ->
          if Enum.any?(imports, predicate), do: [path | acc], else: acc

        {path, imports, _globs}, acc ->
          if Enum.any?(imports, predicate), do: [path | acc], else: acc
      end,
      [],
      @table
    )
  end

  @doc "Compatibility wrapper for `Volt.HMR.GlobGraph.dependents/1`."
  @spec glob_dependents(String.t()) :: [String.t()]
  def glob_dependents(path), do: Volt.HMR.GlobGraph.dependents(path)

  @doc "Remove a file from the graph."
  @spec remove(String.t()) :: :ok
  def remove(path) do
    :ets.delete(@table, path)
    Volt.HMR.GlobGraph.remove(path)
    :ok
  end

  @doc "Clear the entire graph."
  @spec clear :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    Volt.HMR.GlobGraph.clear()
    :ok
  end
end
