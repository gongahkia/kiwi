# kumeyuri

Typed browser wrapper for the kumeyuri WASM renderer.

Use it when a site needs client-side Mermaid-compatible rendering, playback
controls, or a single component that can keep an SSR/static fallback in place
until the WASM renderer succeeds. Use pre-rendered SVG/GIF/APNG/WebP assets when
the page does not need runtime source loading or controls.

## Initialize

```sh
npm install kumeyuri
```

```ts
import initWasm, * as wasm from "kumeyuri/wasm";
import { initKumeyuri, render } from "kumeyuri";

await initKumeyuri({ ...wasm, default: initWasm });

const { svg, frames } = render("graph TD\nA --> B", {
  theme: "github",
  darkTheme: "tokyo-night",
  charset: "unicode",
});
```

## Custom Element

```ts
import initWasm, * as wasm from "kumeyuri/wasm";
import { defineKumeyuriElement, initKumeyuri } from "kumeyuri";

await initKumeyuri({ ...wasm, default: initWasm });
defineKumeyuriElement();
```

```html
<kumeyuri-diagram
  source="sequenceDiagram&#10;Alice->>Bob: hello"
  animate="playback"
  theme="github"
  dark-theme="tokyo-night"
  charset="unicode"
  speed="1.25"
  autoplay
  controls
></kumeyuri-diagram>
```

Source can come from `src`, `source`, legacy `inline`, a
`<script type="text/plain" data-kumeyuri-source>`, or initial text content.

```html
<kumeyuri-diagram src="/diagrams/request-flow.mmd" animate="trace" controls>
  <svg role="img" aria-label="Request flow fallback"></svg>
  <noscript><img src="/diagrams/request-flow.svg" alt="Request flow"></noscript>
</kumeyuri-diagram>
```

If render fails, the element keeps the initial fallback HTML and sets
`data-error`. Without fallback HTML, it renders a `<pre role="alert">`.

## Attributes

| Attribute | Values |
| --- | --- |
| `src` | URL to `.mmd` or `.kumecast` |
| `source` / `inline` | Mermaid source string |
| `animate` | `trace`, `playback`, `transitions`, `none` |
| `theme`, `dark-theme` | built-in kumeyuri theme names |
| `charset` | `ascii`, `unicode` |
| `width`, `padding`, `font` | renderer sizing/font options |
| `speed` | finite number greater than zero |
| `loop` | repeat control playback and set `repeat` render option |
| `autoplay` | start controls playback after render |
| `controls` | mount play/pause, scrub, restart controls |
| `reduced-motion` | `auto`, `reduce`, `no-preference` |
| `svg-animation` | `smil`, `css-keyframes` |
| `csp` | avoid inline control styles; provide CSS yourself |
| `max-source-bytes` | positive integer source-size cap; defaults to `1000000` |
| `fetch-timeout-ms` | positive integer fetch timeout; defaults to `10000` |
| `lazy` | defer first render until visible when `IntersectionObserver` is available |

The element exposes `play()`, `pause()`, `seek(frameIndex)`, and `exportSvg()`.

## CSP

Set `csp` when the page blocks inline styles. The element adds `part` names and
`data-kumeyuri-csp="true"` instead of writing style attributes.

```css
kumeyuri-diagram[csp] { position: relative; }
kumeyuri-diagram [part="controls"] {
  position: absolute;
  right: .5rem;
  bottom: .5rem;
  display: flex;
  gap: .25rem;
}
kumeyuri-diagram [part="play-button"],
kumeyuri-diagram [part="restart-button"],
kumeyuri-diagram [part="scrubber"] {
  min-height: 44px;
}
```

## React

`kumeyuri/react` wraps the same custom element and maps camelCase props to
dashed attributes.

```tsx
import initWasm, * as wasm from "kumeyuri/wasm";
import { KumeyuriDiagram, KumeyuriProvider } from "kumeyuri/react";

const kumeyuriModule = { ...wasm, default: initWasm };

export function App() {
  return (
    <KumeyuriProvider moduleOrLoader={kumeyuriModule}>
      <KumeyuriDiagram
        src="/diagrams/flow.mmd"
        animate="trace"
        theme="github"
        darkTheme="tokyo-night"
        speed={1.25}
        loop
        reducedMotion="auto"
        maxSourceBytes={200000}
        fetchTimeoutMs={5000}
        lazy
        autoplay
        controls
      />
    </KumeyuriProvider>
  );
}
```

## Security

Treat untrusted Mermaid source as untrusted input. kumeyuri does not execute
Mermaid `click` callbacks or embed Mermaid.js, but consumers should still serve
the WASM/module from trusted origins, restrict `src` URLs, use normal CSP, and
sanitize any surrounding user-authored HTML outside this package.

CDN URLs are not documented here until a CDN distribution is shipped.
