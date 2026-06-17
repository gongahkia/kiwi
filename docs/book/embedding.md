# Embedding

Static embeds use generated assets. Live embeds use the WASM renderer and
TypeScript wrapper from the source tree.

CDN URLs are intentionally omitted until the CDN distribution task ships.

## Static Markdown

Generate an SVG and reference it from Markdown:

```bash
kumeyuri render diagrams/flow.mmd --format svg --theme github --dark-theme tokyo-night > diagrams/flow.svg
```

```md
![Flow trace](./diagrams/flow.svg)
```

Generate a raster fallback for sites that strip or disable SVG animation:

```bash
kumeyuri render diagrams/flow.mmd --format gif --theme github --padding 12 > diagrams/flow.gif
```

```md
![Flow trace fallback](./diagrams/flow.gif)
```

## Plain HTML

SVG assets need no JavaScript:

```html
<img src="./diagrams/sequence.svg" alt="Animated sequence playback">
```

For live rendering, initialize the wasm-bindgen module and the TypeScript
wrapper:

```html
<script type="module">
  import initWasm, * as wasm from "./pkg/kumeyuri_render_wasm.js";
  import { defineKumeyuriElement, initKumeyuri } from "./node_modules/kumeyuri/dist/index.js";

  await initKumeyuri({ ...wasm, default: initWasm });
  defineKumeyuriElement();
</script>

<kumeyuri-diagram
  inline="sequenceDiagram&#10;Alice->>Bob: hello"
  animate="playback"
  theme="github"
  dark-theme="tokyo-night"
  speed="1.25"
  autoplay
  controls
></kumeyuri-diagram>
```

## TypeScript API

```ts
import initWasm, * as wasm from "./pkg/kumeyuri_render_wasm.js";
import { initKumeyuri, render } from "kumeyuri";

await initKumeyuri({ ...wasm, default: initWasm });

const { svg, frames } = render("graph TD\nA --> B", {
  theme: "github",
  darkTheme: "tokyo-night",
  charset: "unicode",
});
```

## Custom element attributes

| Attribute | Purpose |
| --- | --- |
| `src` | URL to a Mermaid source file |
| `inline` | Mermaid source string |
| `animate` | `trace`, `playback`, `transitions`, or `none` |
| `theme` | Built-in theme name |
| `dark-theme` | Dark color-scheme theme for SVG output |
| `speed` | Positive playback speed factor |
| `autoplay` | Starts playback when frames are available |
| `controls` | Shows play, pause, scrub, and restart controls |

## mdBook

Put generated assets under the book source tree and link with normal Markdown:

```bash
kumeyuri render docs/book/assets/state.mmd --format svg --theme github > docs/book/assets/state.svg
```

```md
![State transition animation](./assets/state.svg)
```

For terminal-focused pages, render text output and include it as a fenced code
block in the chapter.

To render Mermaid fences during `mdbook build`, install the preprocessor and
configure `book.toml`:

```bash
cargo install --path crates/mdbook-kumeyuri
```

```toml
[preprocessor.kumeyuri]
command = "mdbook-kumeyuri"
format = "svg"
replace = false
theme = "github"
```

Use fenced Mermaid normally:

````md
```mermaid
graph TD
  A --> B
```
````

## Hugo

Copy `integrations/hugo/layouts/shortcodes/kumeyuri.html` into a Hugo site,
render assets into `static/diagrams/`, and call the shortcode:

```md
{{< kumeyuri src="/diagrams/flow.svg" dark="/diagrams/flow.dark.svg" alt="Animated flow trace" caption="Request flow" >}}
```

## Docusaurus and MDX

Put generated assets in `static/diagrams/`:

```mdx
<img src="/diagrams/flow.svg" alt="Animated flow trace" />
```

For live rendering, initialize `initKumeyuri` in a client-only component and use
`<kumeyuri-diagram>` in MDX after that setup component is mounted.
