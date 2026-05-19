defmodule Volt.JS.Patch do
  @moduledoc false

  defstruct [:start, :end, :change]

  @type t :: %__MODULE__{start: non_neg_integer(), end: non_neg_integer(), change: String.t()}

  def new(start_pos, end_pos, change) do
    %__MODULE__{start: start_pos, end: end_pos, change: change}
  end

  def apply(source, patches) do
    OXC.patch_string(source, Enum.map(patches, &Map.from_struct/1))
  end
end
