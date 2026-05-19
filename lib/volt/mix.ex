defmodule Volt.Mix do
  @moduledoc false

  def profile_from_args([name | _]) when is_binary(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> nil
  end

  def profile_from_args(_), do: nil
end
