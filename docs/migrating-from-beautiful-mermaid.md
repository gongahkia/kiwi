# Migrating from beautiful-mermaid

`beautiful-mermaid` is a synchronous TypeScript renderer for SVG and ASCII.
kumeyuri is a Rust renderer with CLI, SVG, raster, TUI, WASM, and text outputs
driven by one frame timeline.

## Main differences

| Area | beautiful-mermaid | kumeyuri |
| --- | --- | --- |
| Runtime | TypeScript package | Rust crates, CLI, WASM wrapper |
| Primary APIs | `renderMermaidSVG`, `renderMermaidASCII` | `kumeyuri render`, Rust crates, WASM `render()` |
| Execution | Synchronous JS API | CLI/Rust sync path; WASM wrapper after initialization |
| Text output | ASCII/Unicode string | Text frame output plus animated TUI playback |
| Web output | SVG string | Animated SVG, raster formats, WASM custom element |
| Diagram coverage | Flowchart, state, sequence, class, ER, XY chart | See `COVERAGE.md` for current supported and static-only roots |

## CLI replacement

beautiful-mermaid is usually called from JS. For build pipelines, replace that
with the CLI:

```sh
kumeyuri render diagram.mmd --format svg --theme github > diagram.svg
kumeyuri render diagram.mmd --format text --charset unicode > diagram.txt
kumeyuri render diagram.mmd --format gif --padding 12 > diagram.gif
```

Use `--format text` for terminal snapshots and `--format svg` for README/docs
assets. Use GIF/APNG/WebP when the publishing target strips SVG animation.

## JavaScript SVG migration

Before:

```ts
import { renderMermaidSVG } from "beautiful-mermaid";

const svg = renderMermaidSVG(source);
```

After, in a browser or bundler that can load the wasm-bindgen output:

```ts
import initWasm, * as wasm from "./pkg/kumeyuri_render_wasm.js";
import { initKumeyuri, render } from "kumeyuri";

await initKumeyuri({ ...wasm, default: initWasm });
const { svg } = render(source, {
  theme: "github",
  darkTheme: "tokyo-night",
});
```

For Node-only build scripts, prefer invoking `kumeyuri render` as a subprocess
unless the script already has a WASM loading path.

## ASCII/text migration

Before:

```ts
import { renderMermaidASCII } from "beautiful-mermaid";

const text = renderMermaidASCII("graph LR; A --> B --> C");
```

After:

```sh
kumeyuri render diagram.mmd --format text --charset unicode
```

Use `--charset ascii` when the output must avoid box-drawing glyphs.

## Theming migration

beautiful-mermaid accepts direct color options such as `bg` and `fg`. kumeyuri
currently exposes built-in themes:

```sh
kumeyuri render diagram.mmd --format svg --theme github
kumeyuri render diagram.mmd --format svg --theme github --dark-theme tokyo-night
```

Current built-ins are `default`, `mono`, `tokyo-night`, `github`, `dracula`,
and `print-mono`. File-based custom themes are tracked separately in `TODO.md`.

## React migration

beautiful-mermaid's synchronous API works well inside `useMemo`. kumeyuri's WASM
wrapper needs one-time async initialization, then synchronous render calls:

```tsx
import initWasm, * as wasm from "./pkg/kumeyuri_render_wasm.js";
import { initKumeyuri, render } from "kumeyuri";

await initKumeyuri({ ...wasm, default: initWasm });

function Diagram({ source }: { source: string }) {
  const output = React.useMemo(() => render(source, { theme: "github" }), [source]);
  return <div dangerouslySetInnerHTML={{ __html: output.svg }} />;
}
```

When you want playback controls, use the custom element instead:

```html
<kumeyuri-diagram src="/diagrams/flow.mmd" animate="trace" theme="github" controls></kumeyuri-diagram>
```

## Parity checks

Run the comparison fixtures before switching renderer output in a docs or CI
pipeline:

```sh
npm run test:bench:beautiful-mermaid
scripts/generate-static-comparison.sh
```

Review `docs/comparison/static-parity.md` for current match/loss notes. Do not
assume a byte-identical text layout for multi-layer graphs; keep visual diffs
visible when output changes.
