defmodule Volt.HMR.GlobGraph do
  @moduledoc "Tracks `import.meta.glob()` ownership for HMR invalidation."

  @table :volt_hmr_glob_graph

  @doc "Create the glob graph ETS table."
  def create_table do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    :ok
  end

  @doc "Store glob patterns owned by an importer."
  def update(importer, globs) do
    :ets.insert(@table, {importer, globs})
    :ok
  end

  @doc "Extract and store `import.meta.glob()` patterns from source."
  def update_from_source(path, source) do
    globs =
      source
      |> Volt.JS.Transforms.GlobImports.patterns(Path.basename(path))
      |> Enum.map(&expand_glob_pattern(&1, Path.dirname(path)))

    update(path, globs)
  end

  @doc "Find all files with an `import.meta.glob()` pattern matching `path`."
  def dependents(path) do
    :ets.foldl(
      fn {importer, globs}, acc ->
        if glob_match?(globs, path), do: [importer | acc], else: acc
      end,
      [],
      @table
    )
  end

  def remove(path) do
    :ets.delete(@table, path)
    :ok
  end

  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  defp expand_glob_pattern("!" <> pattern, base_dir), do: "!" <> Path.expand(pattern, base_dir)
  defp expand_glob_pattern(pattern, base_dir), do: Path.expand(pattern, base_dir)

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
end
