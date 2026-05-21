defmodule Volt.Builder.OutputFile do
  @moduledoc false

  defstruct path: nil,
            size: 0,
            assets: [],
            chunk_id: nil,
            type: nil
end
