defmodule Volt.JS.Transforms.DynamicImports.Replacement do
  @moduledoc false

  defstruct start: nil,
            end: nil,
            index: nil,
            template: "",
            pattern: "",
            query: ""
end
