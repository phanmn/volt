defmodule Volt.Config.Build do
  @moduledoc "Normalized production build configuration."

  defstruct entry: "assets/js/app.ts",
            outdir: "priv/static/assets",
            public_dir: false,
            target: :es2020,
            minify: true,
            sourcemap: true,
            hash: true,
            code_splitting: true,
            tree_shaking: true,
            format: :iife,
            mode: :production,
            env_prefix: "VOLT_",
            asset_url_prefix: "/assets",
            external: [],
            aliases: %{},
            chunks: %{},
            plugins: [],
            resolve_dirs: [],
            root: "assets",
            sources: ["**/*.{js,ts,jsx,tsx,vue}"],
            ignore: ["node_modules/**", "vendor/**"],
            import_source: nil,
            vapor: false,
            custom_renderer: false,
            module_types: %{}
end
