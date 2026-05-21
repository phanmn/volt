defmodule Mix.Tasks.Volt.Profile do
  @moduledoc "Shared profile argument parsing for Volt Mix tasks."

  def from_args([name | _]) when is_binary(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> nil
  end

  def from_args(_), do: nil
end
