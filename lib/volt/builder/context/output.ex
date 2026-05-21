defmodule Volt.Builder.OutputContext do
  @moduledoc false

  defstruct plugins: [],
            external_set: MapSet.new(),
            external_globals: %{},
            workers: %{},
            worker_results: %{}
end
