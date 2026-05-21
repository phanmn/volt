defmodule Volt.JS.ImportExtractor.Result do
  @moduledoc false

  @type import_type :: :static | :dynamic
  @type t :: %__MODULE__{imports: [{import_type(), String.t()}], workers: [String.t()]}

  defstruct imports: [], workers: []
end
