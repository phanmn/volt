# Static Assets

Images, fonts, SVGs, media, WebAssembly, PDFs, and text files are handled automatically when referenced from JavaScript or CSS.

Volt follows Vite-style semantics in both dev and production:

- JavaScript imports become modules that export a string.
- CSS `url(...)` references are resolved from the CSS file that contains them.
- `new URL("./asset.ext", import.meta.url)` participates in the production graph.
- Production builds copy referenced files with content-hashed names and rewrite URLs to `/assets/...`.

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

Relative `url(...)` references inside CSS are copied and rewritten in production:

```css
.logo {
  background-image: url('./images/logo.svg');
}
```

becomes something like:

```css
.logo {
  background-image: url('/assets/logo-a1b2c3d4.svg');
}
```

Absolute paths, fragments, data URLs, and remote URLs are preserved.

## Supported formats

Images (`.svg`, `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.avif`, `.ico`), fonts (`.woff`, `.woff2`, `.ttf`, `.otf`, `.eot`), media (`.mp4`, `.webm`, `.ogg`, `.mp3`, `.wav`), and other formats (`.pdf`, `.wasm`, `.txt`).
