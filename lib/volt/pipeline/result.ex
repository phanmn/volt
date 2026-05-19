defmodule Volt.Pipeline.Result do
  @moduledoc false

  defstruct code: "", sourcemap: nil, css: nil, hashes: nil, warnings: []

  @type t :: %__MODULE__{
          code: String.t(),
          sourcemap: String.t() | nil,
          css: String.t() | nil,
          hashes: Volt.Pipeline.Hashes.t() | nil,
          warnings: [term()]
        }
end

defmodule Volt.Pipeline.Hashes do
  @moduledoc false

  defstruct template: nil, style: nil, script: nil

  @type t :: %__MODULE__{
          template: String.t() | nil,
          style: String.t() | nil,
          script: String.t() | nil
        }
end
