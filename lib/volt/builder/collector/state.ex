defmodule Volt.Builder.Collector.State do
  @moduledoc false

  defstruct root: nil,
            ctx: nil,
            files: [],
            seen: MapSet.new(),
            used_labels: MapSet.new(),
            dep_map: %{},
            workers: %{},
            specifier_labels: %{},
            path_labels: %{}
end
