defmodule Volt.JS.Query do
  @moduledoc false

  @asset_query_keys ~w(raw url inline no-inline import)

  def split(specifier) do
    case String.split(specifier, "?", parts: 2) do
      [path, query] -> {path, query}
      [path] -> {path, ""}
    end
  end

  def append(path, ""), do: path
  def append(path, query), do: path <> "?" <> query

  def decode(""), do: %{}
  def decode(query), do: URI.decode_query(query)

  def asset_module_query?(query) do
    query
    |> decode()
    |> Map.keys()
    |> Enum.any?(&(&1 in @asset_query_keys))
  end
end
