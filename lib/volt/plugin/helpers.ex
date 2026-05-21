defmodule Volt.Plugin.Helpers do
  @moduledoc false

  def cache_hash(nil), do: nil
  def cache_hash(""), do: nil
  def cache_hash(value), do: :erlang.phash2(value) |> Integer.to_string(16)
end
