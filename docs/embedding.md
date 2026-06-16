# Embedding kumeyuri diagrams

This page covers current local/npm workflows. CDN URLs are intentionally omitted until the CDN distribution task ships.

## GitHub README

Generate an animated SVG or raster fallback into the repo and reference it with normal Markdown.

```bash
kumeyuri render diagrams/flow.mmd --format svg --theme github --charset unicode > diagrams/flow.svg
kumeyuri render diagrams/flow.mmd --format gif --theme github --padding 12 > diagrams/flow.gif
```

```md
![Flow trace](./diagrams/flow.svg)

<!-- Raster fallback for surfaces that strip SVG animation. -->
![Flow trace](./diagrams/flow.gif)
```

For a code-block fallback:

```bash
kumeyuri render diagrams/flow.mmd --format text --charset unicode > diagrams/flow.txt
```

## Hugo

Place rendered assets under `static/diagrams/`, then use a shortcode.

```go-html-template
{{/* layouts/shortcodes/kumeyuri.html */}}
<figure class="kumeyuri-diagram">
  <img src="{{ .Get "src" }}" alt="{{ .Get "alt" }}">
  {{ with .Get "caption" }}<figcaption>{{ . }}</figcaption>{{ end }}
</figure>
```

```md
{{< kumeyuri src="/diagrams/flow.svg" alt="Animated flow trace" caption="Request flow" >}}
```

## Docusaurus

Put generated assets in `static/diagrams/` and use Markdown or MDX.

```mdx
<img src="/diagrams/flow.svg" alt="Animated flow trace" />
```

For the WASM player, initialize the npm wrapper in a client-only component.

```tsx
import { useEffect } from "react";
import initWasm, * as wasm from "./pkg/kumeyuri_render_wasm.js";
import { defineKumeyuriElement, initKumeyuri } from "kumeyuri";

export function KumeyuriSetup() {
  useEffect(() => {
    void initKumeyuri({ ...wasm, default: initWasm }).then(() => {
      defineKumeyuriElement();
    });
  }, []);
  return null;
}
```

```mdx
<KumeyuriSetup />
<kumeyuri-diagram
  src="/diagrams/flow.mmd"
  animate="trace"
  theme="github"
  speed="1.25"
  autoplay
  controls
/>
```

## mdBook

Put generated assets next to the chapter or under `src/diagrams/`.

```bash
kumeyuri render src/diagrams/state.mmd --format svg --theme github > src/diagrams/state.svg
```

```md
![State transition animation](./diagrams/state.svg)
```

For terminal-only books or print output, use text:

```bash
kumeyuri render src/diagrams/state.mmd --format text --charset unicode > src/diagrams/state.txt
```

````md
```text
{{#include diagrams/state.txt}}
```
````

## Plain HTML

Static asset embedding needs no JavaScript.

```html
<img src="./diagrams/sequence.svg" alt="Animated sequence playback">
```

For live rendering, load the generated wasm-bindgen module and the typed npm wrapper.

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
  speed="1.25"
  autoplay
  controls
></kumeyuri-diagram>
```
