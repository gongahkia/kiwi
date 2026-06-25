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

For one SVG that adapts to the viewer's colour scheme:

```bash
kumeyuri render diagrams/flow.mmd --format svg --theme github --dark-theme tokyo-night > diagrams/flow.svg
```

For paired assets, render a light file and a `.dark.svg` file, then swap them with CSS in static-site templates.

```bash
kumeyuri render diagrams/flow.mmd --format svg --theme github > diagrams/flow.svg
kumeyuri render diagrams/flow.mmd --format svg --theme tokyo-night > diagrams/flow.dark.svg
```

```html
<span class="kumeyuri-mermaid-swap">
  <img class="mermaid-light" src="/diagrams/flow.svg" alt="Flow trace">
  <img class="mermaid-dark" src="/diagrams/flow.dark.svg" alt="Flow trace">
</span>
```

```css
.mermaid-dark {
  display: none;
}

@media (prefers-color-scheme: dark) {
  .mermaid-light {
    display: none;
  }

  .mermaid-dark {
    display: inline;
  }
}
```

## Hugo

Place rendered assets under `static/diagrams/`, then use the bundled shortcode
at `integrations/hugo/layouts/shortcodes/kumeyuri.html`.

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
import initWasm, * as wasm from "kumeyuri/wasm";
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
  dark-theme="tokyo-night"
  speed="1.25"
  autoplay
  controls
/>
```

## React

Install the browser package and initialize it in a client-rendered component.
The React subpath renders the same `<kumeyuri-diagram>` element and maps
`darkTheme` to `dark-theme` plus boolean props to omitted/present attributes.

```tsx
import initWasm, * as wasm from "kumeyuri/wasm";
import { KumeyuriDiagram, KumeyuriProvider } from "kumeyuri/react";

const kumeyuriModule = { ...wasm, default: initWasm };

export function Diagram() {
  return (
    <KumeyuriProvider moduleOrLoader={kumeyuriModule}>
      <KumeyuriDiagram
        src="/diagrams/flow.mmd"
        animate="trace"
        theme="github"
        darkTheme="tokyo-night"
        speed={1.25}
        autoplay
        controls
      />
    </KumeyuriProvider>
  );
}
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
  import initWasm, * as wasm from "kumeyuri/wasm";
  import { defineKumeyuriElement, initKumeyuri } from "./node_modules/kumeyuri/dist/index.js";

  await initKumeyuri({ ...wasm, default: initWasm });
  defineKumeyuriElement();
</script>

<kumeyuri-diagram
  source="sequenceDiagram&#10;Alice->>Bob: hello"
  animate="playback"
  theme="github"
  dark-theme="tokyo-night"
  speed="1.25"
  autoplay
  controls
></kumeyuri-diagram>
```

Production live embeds should include fallback HTML:

```html
<kumeyuri-diagram src="/diagrams/flow.mmd" animate="trace" controls csp lazy max-source-bytes="200000" fetch-timeout-ms="5000">
  <svg role="img" aria-label="Request flow fallback"></svg>
  <noscript><img src="/diagrams/flow.svg" alt="Request flow"></noscript>
</kumeyuri-diagram>
```

With `csp`, style controls from site CSS:

```css
kumeyuri-diagram[csp] { position: relative; }
kumeyuri-diagram [part="controls"] { position: absolute; right: .5rem; bottom: .5rem; display: flex; gap: .25rem; }
kumeyuri-diagram [part="play-button"],
kumeyuri-diagram [part="restart-button"],
kumeyuri-diagram [part="scrubber"] { min-height: 44px; }
```
