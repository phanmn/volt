defmodule Volt.Pipeline.Result do
  @moduledoc false

  defmodule Hashes do
    @moduledoc false

    defstruct template: nil, style: nil, script: nil

    @type t :: %__MODULE__{
            template: String.t() | nil,
            style: String.t() | nil,
            script: String.t() | nil
          }
  end

  defstruct code: "", type: :js, sourcemap: nil, css: nil, hashes: nil, warnings: []

  @type type :: :js | :css

  @type t :: %__MODULE__{
          code: String.t(),
          type: type(),
          sourcemap: String.t() | nil,
          css: String.t() | nil,
          hashes: Hashes.t() | nil,
          warnings: [term()]
        }
end
