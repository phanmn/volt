defmodule Volt.Builder.Context do
  @moduledoc false

  defstruct node_modules: nil,
            resolve_dirs: [],
            aliases: %{},
            plugins: [],
            external: MapSet.new(),
            external_globals: %{},
            loaders: %{},
            module_types: %{},
            import_source: nil,
            target: "",
            define: %{},
            asset_url_prefix: "/assets"
end
