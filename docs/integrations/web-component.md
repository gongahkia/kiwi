# Web Component

Use `packages/kumeyuri` when a site needs live browser rendering instead of
pre-rendered assets. Prefer static SVG/GIF/APNG/WebP assets when the page only
needs a finished diagram.

```ts
import initWasm, * as wasm from "./pkg/kumeyuri_render_wasm.js";
import { defineKumeyuriElement, initKumeyuri } from "kumeyuri";

await initKumeyuri({ ...wasm, default: initWasm });
defineKumeyuriElement();
```

```html
<kumeyuri-diagram
  src="/diagrams/flow.mmd"
  animate="trace"
  theme="github"
  dark-theme="tokyo-night"
  charset="unicode"
  speed="1.25"
  controls
></kumeyuri-diagram>
```

## SSR Fallback

Keep a fallback inside the element. It is replaced only after WASM render
succeeds and restored if render fails.

```html
<kumeyuri-diagram src="/diagrams/flow.mmd" animate="trace" controls>
  <svg role="img" aria-label="Request flow fallback"></svg>
  <noscript><img src="/diagrams/flow.svg" alt="Request flow"></noscript>
</kumeyuri-diagram>
```

For inline source without putting Mermaid in an attribute:

```html
<kumeyuri-diagram animate="trace" controls>
  <svg role="img" aria-label="Request flow fallback"></svg>
  <script type="text/plain" data-kumeyuri-source>
graph TD
  Browser --> Edge
  Edge --> App
  </script>
</kumeyuri-diagram>
```

Source precedence is `src`, `source`, `inline`, script source, then initial text
content.

## Controls API

```ts
const diagram = document.querySelector("kumeyuri-diagram");
diagram.play();
diagram.pause();
diagram.seek(2);
const svg = diagram.exportSvg();
```

`autoplay` starts playback unless `reduced-motion="reduce"` or the user's
`prefers-reduced-motion: reduce` media query matches in `auto` mode. `loop`
wraps playback when the last frame is reached.

## CSP Mode

Set `csp` when inline style attributes are blocked. The element adds stable
`part` names and `data-kumeyuri-csp="true"` instead.

```html
<kumeyuri-diagram src="/diagrams/flow.mmd" animate="trace" controls csp></kumeyuri-diagram>
```

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

## Security

Do not fetch arbitrary user-controlled `src` URLs. Serve the WASM/module from a
trusted origin, keep normal site CSP, and sanitize surrounding user-authored HTML
outside kumeyuri. kumeyuri does not execute Mermaid `click` callbacks or embed
Mermaid.js.
