# Static Assets

Images, fonts, SVGs, media, WebAssembly, PDFs, and text files are handled automatically when referenced from JavaScript.

Volt follows Vite-style asset import semantics in both dev and production:

- JavaScript imports become modules that export a string.
- `new URL("./asset.ext", import.meta.url)` participates in the production graph.
- Production builds copy referenced files with content-hashed names and rewrite JavaScript URLs to `/assets/...`.

CSS is parsed and bundled by LightningCSS through Vize. Relative CSS `url(...)` references are preserved today; use JavaScript asset imports or `new URL(..., import.meta.url)` when you need Volt to hash and rewrite an asset. CSS URL rewriting will be added once Volt can do it through parser-backed LightningCSS metadata rather than hand-rolled CSS parsing.

## Default imports

Small files under the inline limit are inlined as base64 data URIs:

```javascript
import icon from './icon.svg'
// icon = "data:image/svg+xml;base64,..."
```

Larger files are copied to the output directory and exported as public URLs:

```javascript
import photo from './photo.jpg'
// photo = "/assets/photo-a1b2c3d4.jpg"
```

The default inline limit is 4 KB.

## Query modes

Use query suffixes when you need a specific representation:

```javascript
import source from './message.txt?raw'
import url from './logo.svg?url'
import inlineIcon from './icon.svg?inline'
import fileUrl from './small-icon.svg?no-inline'
```

| Query | Result |
| --- | --- |
| `?raw` | exports file contents as a string |
| `?url` | exports a public URL |
| `?inline` | exports a data URI even when the file is larger than the inline limit |
| `?no-inline` | exports a public URL even when the file is small |

## `new URL(..., import.meta.url)`

Relative asset URL constructors are rewritten during production builds:

```javascript
const logo = new URL('./logo.svg', import.meta.url).href
```

The referenced file is copied with a content hash and the bundled JavaScript points at the emitted `/assets/...` URL.

Only relative specifiers that resolve to known asset extensions are rewritten. Remote URLs, absolute URLs, and non-asset modules are left unchanged.

## CSS URLs

CSS files are parsed, transformed, and bundled by LightningCSS through Vize. Relative `url(...)` references currently remain as CSS authored them:

```css
.logo {
  background-image: url('./images/logo.svg');
}
```

Use this for URLs that are already correct at runtime, such as Phoenix static paths (`/images/logo.svg`) or external/data URLs. For assets that need Volt-managed hashing, import the asset from JavaScript instead:

```javascript
import logo from './images/logo.svg?url'
document.documentElement.style.setProperty('--logo-url', `url(${logo})`)
```

## Phoenix static files and optional public directory

In Phoenix apps, stable root files usually belong in `priv/static` and are served by Phoenix through `Plug.Static`:

```text
priv/static/favicon.svg -> /favicon.svg
priv/static/robots.txt  -> /robots.txt
```

Volt's asset pipeline is for files referenced by JavaScript when you want dependency tracking, hashing, and URL rewriting.

For Vite migration compatibility, Volt also supports an optional `public_dir`. It is disabled by default. When enabled, files in that directory are served and copied without transformation:

```elixir
config :volt,
  public_dir: "public"
```

```text
public/favicon.svg -> /favicon.svg
```

Public directory files are not hashed and are not processed by import query modes. Prefer module imports for assets referenced by JavaScript when you want hashing and dependency tracking.

## Supported formats

Images (`.svg`, `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.avif`, `.ico`), fonts (`.woff`, `.woff2`, `.ttf`, `.otf`, `.eot`), media (`.mp4`, `.webm`, `.ogg`, `.mp3`, `.wav`), and other formats (`.pdf`, `.wasm`, `.txt`).
