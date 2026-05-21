defmodule Volt.JS.Query do
  @moduledoc """
  Helpers for import specifiers that include URL query parameters.

  Volt keeps query strings as part of module identity, but most filesystem work
  must operate on the path portion only. This module centralizes those small
  operations so dev-server, build graph, and asset handling all interpret query
  modes consistently.
  """

  @asset_query_keys ~w(raw url inline no-inline import)

  @doc """
  Splits an import specifier into `{path, query}` without the leading `?`.
  """
  @spec split(String.t()) :: {String.t(), String.t()}
  def split(specifier) do
    case String.split(specifier, "?", parts: 2) do
      [path, query] -> {path, query}
      [path] -> {path, ""}
    end
  end

  @doc """
  Appends a query string to `path`, preserving paths with no query.
  """
  @spec append(String.t(), String.t()) :: String.t()
  def append(path, query), do: Volt.URL.append_query(path, query)

  @doc """
  Decodes a query string into a map.
  """
  @spec decode(String.t()) :: %{optional(String.t()) => String.t()}
  def decode(""), do: %{}
  def decode(query), do: URI.decode_query(query)

  @doc """
  Returns true when a query requests an asset module response.
  """
  @spec asset_module_query?(String.t()) :: boolean()
  def asset_module_query?(query) do
    query
    |> decode()
    |> Map.keys()
    |> Enum.any?(&(&1 in @asset_query_keys))
  end
end
