defmodule Volt.Config.Profile do
  @moduledoc "Profile argument parsing for Volt Mix tasks."

  def from_args([name | _]) when is_binary(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> nil
  end

  def from_args(_), do: nil
end
