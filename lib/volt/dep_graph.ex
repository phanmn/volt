defmodule Volt.DepGraph do
  @moduledoc """
  ETS-backed module dependency graph.

  Tracks which files import which specifiers and which `import.meta.glob()`
  patterns they own, enabling reverse lookups for HMR propagation — "what
  depends on this file?"
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
    :ets.insert(@table, {path, imports, globs})
    :ok
  end

  @doc "Update imports and glob patterns from source and compiled code."
  @spec update_from_source(String.t(), String.t(), String.t()) :: :ok
  def update_from_source(path, source, compiled_code) do
    imports =
      case OXC.imports(compiled_code, Path.basename(path)) do
        {:ok, imports} -> imports
        _ -> []
      end

    globs =
      source
      |> Volt.JS.Transforms.GlobImports.patterns(Path.basename(path))
      |> Enum.map(&expand_glob_pattern(&1, Path.dirname(path)))

    update(path, imports, globs)
  end

  defp expand_glob_pattern("!" <> pattern, base_dir), do: "!" <> Path.expand(pattern, base_dir)
  defp expand_glob_pattern(pattern, base_dir), do: Path.expand(pattern, base_dir)

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

  @doc "Find all files with an `import.meta.glob()` pattern matching `path`."
  @spec glob_dependents(String.t()) :: [String.t()]
  def glob_dependents(path) do
    :ets.foldl(
      fn
        {_importer, _imports}, acc ->
          acc

        {importer, _imports, globs}, acc ->
          if glob_match?(globs, path), do: [importer | acc], else: acc
      end,
      [],
      @table
    )
  end

  defp glob_match?(globs, path) do
    {negative, positive} = Enum.split_with(globs, &String.starts_with?(&1, "!"))

    positive_match? = Enum.any?(positive, &pattern_match?(&1, path))
    negative_match? = Enum.any?(negative, fn "!" <> pattern -> pattern_match?(pattern, path) end)

    positive_match? and not negative_match?
  end

  defp pattern_match?(pattern, path) do
    pattern
    |> GlobEx.compile!()
    |> GlobEx.match?(path)
  end

  @doc "Remove a file from the graph."
  @spec remove(String.t()) :: :ok
  def remove(path) do
    :ets.delete(@table, path)
    :ok
  end

  @doc "Clear the entire graph."
  @spec clear :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end
end
