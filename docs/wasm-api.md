# WASM / TypeScript API

The browser bundle has two layers:

| Layer | Source | Purpose |
| --- | --- | --- |
| wasm-bindgen module | `crates/kumeyuri-render-wasm` | Exposes `render(source, options)` and `WasmRenderer` |
| TypeScript wrapper | `packages/kumeyuri` | Normalizes output and defines `<kumeyuri-diagram>` |

Build the wrapper with:

```sh
npm --workspace kumeyuri run build
```

## Initialize

```ts
import initWasm, * as wasm from "./pkg/kumeyuri_render_wasm.js";
import { initKumeyuri, render } from "kumeyuri";

await initKumeyuri({ ...wasm, default: initWasm });

const output = render("graph TD\nA --> B", {
  theme: "github",
  darkTheme: "tokyo-night",
  charset: "unicode",
});
```

`render()` throws until `initKumeyuri()` has installed an active client.

## Direct client

Use `createKumeyuri()` when the caller owns wasm initialization:

```ts
import { createKumeyuri } from "kumeyuri";

const client = createKumeyuri(wasm);
const output = client.render("sequenceDiagram\nAlice->>Bob: hello");
```

## Render options

| Option | Type | Notes |
| --- | --- | --- |
| `theme` | built-in theme name | Defaults to `default` |
| `darkTheme` | built-in theme name | Adds dark-mode colors to SVG |
| `charset` | `ascii` or `unicode` | Overrides the theme charset |
| `width` | positive number | Pads text frames to at least this many cells |
| `padding` | number | SVG padding in pixels |
| `font` | string | SVG font family |
| `speed` | number | Animation speed factor |
| `repeat` | boolean | Timeline repeat flag |
| `svgAnimation` | `smil` or `css-keyframes` | Selects SVG animation strategy |

Built-in themes:

```ts
type KumeyuriTheme =
  | "default"
  | "mono"
  | "tokyo-night"
  | "github"
  | "dracula"
  | "solarized-light"
  | "solarized-dark"
  | "nord"
  | "catppuccin-mocha"
  | "high-contrast"
  | "print-mono";
```

Unknown option keys are rejected by the wasm layer.

## Render output

```ts
interface KumeyuriRenderOutput {
  svg: string;
  frames: Array<{
    text: string;
    durationMs: number;
  }>;
}
```

`svg` is the complete animated SVG string. `frames` are text snapshots from the
same timeline and can drive custom controls, captions, or debug displays.

## Custom element

Register the element:

```ts
import { defineKumeyuriElement, initKumeyuri } from "kumeyuri";

await initKumeyuri({ ...wasm, default: initWasm });
defineKumeyuriElement();
```

Use it in HTML:

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

SSR/static fallback HTML can stay inside the element until render succeeds:

```html
<kumeyuri-diagram src="/diagrams/flow.mmd" animate="trace" controls>
  <svg role="img" aria-label="Request flow fallback"></svg>
  <noscript><img src="/diagrams/flow.svg" alt="Request flow"></noscript>
</kumeyuri-diagram>
```

For long inline sources, keep the source in a non-executed script tag:

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

Supported attributes:

| Attribute | Purpose |
| --- | --- |
| `src` | Fetch Mermaid source from a URL; `.kumecast` uses `renderCast()` |
| `source` | Render Mermaid source from an attribute |
| `inline` | Legacy alias for `source` |
| `animate` | Inject `trace`, `playback`, `transitions`, or `none` directive |
| `theme` | Base built-in theme |
| `dark-theme` | SVG dark-mode built-in theme |
| `charset` | `ascii` or `unicode` |
| `width` | Positive minimum text-frame width |
| `padding` | Non-negative SVG padding |
| `font` | SVG font family |
| `speed` | Positive playback speed factor |
| `loop` | Repeat controls playback and set render option `repeat` |
| `autoplay` | Start controls playback after render |
| `controls` | Mount play/pause, restart, and scrub controls |
| `reduced-motion` | `auto`, `reduce`, or `no-preference` |
| `svg-animation` | `smil` or `css-keyframes` |
| `csp` | Do not write inline styles for controls |

If `src`, `source`, `inline`, and script source are absent, the element uses its
initial text content as Mermaid source.

The custom element exposes:

```ts
interface KumeyuriDiagramElement extends HTMLElement {
  play(): void;
  pause(): void;
  seek(frameIndex: number): void;
  exportSvg(): string;
}
```

Use `csp` when a site blocks inline styles. The element writes `part="controls"`,
`part="play-button"`, `part="restart-button"`, `part="scrubber"`, and
`data-kumeyuri-csp="true"` so page CSS can style the controls.

## React

React apps can use the `kumeyuri/react` subpath. `KumeyuriProvider` initializes
the WASM module and defines the custom element on the client; `KumeyuriDiagram`
renders the element with typed props.

```tsx
import initWasm, * as wasm from "./pkg/kumeyuri_render_wasm.js";
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
        charset="unicode"
        speed={1.25}
        reducedMotion="auto"
        autoplay
        controls
      />
    </KumeyuriProvider>
  );
}
```

The component maps `darkTheme` to `dark-theme` and omits false boolean
attributes, so it works across React 18/19 custom-element behavior.

## Error behavior

Parse, option, fetch, and render failures surface as thrown errors from the
wrapper API. The custom element stores the error message in `data-error` and
restores its initial fallback HTML. If no fallback HTML exists, it renders a
`<pre data-kumeyuri-error role="alert">` with the error message.
