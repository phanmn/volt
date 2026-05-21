defmodule Volt.JS.Transforms.GlobImports.Call do
  @moduledoc false

  defstruct start: nil,
            end: nil,
            patterns: [],
            eager: false,
            import: nil,
            query: "",
            base: nil
end
