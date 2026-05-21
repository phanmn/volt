defmodule Volt.Assets.Query do
  @moduledoc "Query helpers for asset module request modes."

  @module_keys ~w(raw url inline no-inline import)

  def decode(query), do: Volt.URL.decode_query(query)

  def module_request?(query) do
    query
    |> decode()
    |> Map.keys()
    |> Enum.any?(&(&1 in @module_keys))
  end
end
