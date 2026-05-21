defmodule Volt.JS.PrebundleEntry.Import do
  @moduledoc false

  @type t :: %__MODULE__{default: String.t(), from: String.t()}

  defstruct [:default, :from]

  def default(name, from: specifier), do: %__MODULE__{default: name, from: specifier}
end
