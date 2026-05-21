defmodule Volt.Cache do
  @moduledoc """
  ETS-backed module cache keyed by `{path, mtime}`.

  Caches compiled output so repeated requests for unchanged files
  skip the compilation step entirely.
  """

  @table :volt_cache

  @type entry :: %{
          code: String.t(),
          sourcemap: String.t() | nil,
          css: String.t() | nil,
          hashes: Volt.Pipeline.Result.Hashes.t() | nil,
          content_type: String.t()
        }

  @doc "Create the cache ETS table. Called once from Application.start/2."
  @spec create_table :: :ok
  def create_table do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    :ok
  end

  @doc "Look up a cached entry. Returns `nil` on miss."
  @spec get(String.t(), integer()) :: entry() | nil
  def get(path, mtime) do
    case :ets.lookup(@table, {path, mtime}) do
      [{_, entry}] -> entry
      [] -> nil
    end
  end

  @doc "Look up any cached entry for a file path regardless of mtime."
  @spec get_file(String.t()) :: entry() | nil
  def get_file(path) do
    case :ets.match_object(@table, {{path, :_}, :_}) do
      [{{^path, _mtime}, entry} | _] -> entry
      [] -> nil
    end
  end

  @doc "Store a compiled entry."
  @spec put(String.t(), integer(), entry()) :: :ok
  def put(path, mtime, entry) do
    :ets.insert(@table, {{path, mtime}, entry})
    :ok
  end

  @doc "Evict all entries for a cache key (any mtime)."
  @spec evict(String.t()) :: :ok
  def evict(key) do
    :ets.match_delete(@table, {{key, :_}, :_})
    :ok
  end

  @doc "Evict all cache entries derived from a file path, including variant keys like `path <> \"?import\"`."
  @spec evict_file(String.t()) :: :ok
  def evict_file(path) do
    evict(path)
    evict(Volt.URL.append_query(path, "import"))
    :ok
  end

  @doc "Clear all cached entries."
  @spec clear :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end
end
