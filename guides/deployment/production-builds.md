# Production Builds

```bash
mix volt.build
```

```text
Building Tailwind CSS...
  app-1a2b3c4d.css  23.9 KB
Built Tailwind in 43ms
Building "assets/js/app.ts"...
  app-5e6f7a8b.js  128.4 KB
  manifest.json  2 entries
Built in 15ms
```

Reads configuration from `config :volt`. CLI flags override config values.

## What production builds do

Production builds run the same framework/plugin compilation pipeline as the dev server, then apply build-only graph and output steps:

- expands `import.meta.glob()` and simple relative dynamic import variables
- rewrites `new URL("./asset.ext", import.meta.url)` through the asset pipeline
- copies JavaScript and CSS-referenced assets with content hashes
- rewrites CSS `url(...)` references to `/assets/...`
- tree-shakes, minifies, and optionally code-splits JavaScript
- writes a manifest that Phoenix can use for digested asset paths
- copies the configured public directory to the static root without transforming files

## Public directory

Files in `public_dir` are copied as-is to the static root. With the default output directory, JavaScript and CSS are written below `priv/static/assets`, while public files are copied to `priv/static`:

```text
public/favicon.svg      -> priv/static/favicon.svg
public/robots.txt       -> priv/static/robots.txt
assets/js/app.ts        -> priv/static/assets/js/app-a1b2c3d4.js
```

Reference public files with root-absolute URLs such as `/favicon.svg`. They are not transformed, hashed, or included in the module graph.

Configure or disable the directory with:

```elixir
config :volt,
  public_dir: "public"

# or
config :volt,
  public_dir: false
```

CLI: `mix volt.build --public-dir path/to/public`.

## Source Maps

- `sourcemap: true` — write `.map` files and append `//# sourceMappingURL` comment (default)
- `sourcemap: :hidden` — write `.map` files without the URL comment (for Sentry, Datadog, etc.)
- `sourcemap: false` — no source maps

CLI: `--sourcemap hidden` or `--sourcemap false`.

## External Modules

Exclude packages that the host page already provides:

```elixir
config :volt, external: ~w(phoenix phoenix_html phoenix_live_view)
```

Or per-build: `mix volt.build --external phoenix --external phoenix_html`

## Module Preloading

For code-split builds, `Volt.Preload.tags/2` generates `<link rel="modulepreload">` tags from the build manifest to preload async chunks:

```heex
<%= Volt.Preload.tags("priv/static/assets/js/manifest.json", "/assets/js") %>
```

## Deploy Alias

The installer generates an `assets.deploy` alias:

```elixir
"assets.deploy": ["volt.build --tailwind", "phx.digest"]
```

This builds assets with content hashes, then generates the Phoenix digest manifest for CDN deployment.
