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
  src="/diagrams/flow.mmd"
  animate="trace"
  theme="github"
  dark-theme="tokyo-night"
  speed="1.25"
  autoplay
  controls
></kumeyuri-diagram>
```

Supported attributes:

| Attribute | Purpose |
| --- | --- |
| `src` | Fetch Mermaid source from a URL |
| `inline` | Render Mermaid source from an attribute |
| `animate` | Inject `trace`, `playback`, `transitions`, or `none` directive |
| `theme` | Base built-in theme |
| `dark-theme` | SVG dark-mode built-in theme |
| `speed` | Positive playback speed factor |
| `autoplay` | Start controls playback after render |
| `controls` | Mount play/pause, restart, and scrub controls |

If `src` and `inline` are both absent, the element uses its initial text
content as Mermaid source.

## Error behavior

Parse, option, fetch, and render failures surface as thrown errors from the
wrapper API. The custom element stores the error message in `data-error` and
does not replace the element content with a partial render.
