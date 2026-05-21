defmodule Volt.DevServer.Config do
  @moduledoc false

  defstruct root: nil,
            public_dir: nil,
            prefix: "/assets",
            target: "",
            import_source: nil,
            vapor: false,
            custom_renderer: false,
            plugins: [],
            aliases: %{},
            node_modules: nil,
            resolve_dirs: [],
            module_types: %{},
            define: %{}
end
