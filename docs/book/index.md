# kumeyuri

kumeyuri renders Mermaid diagrams as animated text artifacts.

These docs describe the current source tree. The crates.io, npm, and CDN publish
tasks are still pending in `TODO.md`, so install and embed examples use local
source builds or generated assets.

## What it renders

| Surface | Output |
| --- | --- |
| Terminal | Static text and interactive TUI playback |
| SVG | Animated SVG with frame groups, SMIL, CSS fallback, and text metadata |
| Raster | GIF, APNG, and WebP animation outputs |
| Browser | WASM renderer plus typed TypeScript API and `<kumeyuri-diagram>` custom element |

## Supported Mermaid families

| Family | Headers |
| --- | --- |
| Flowcharts | `graph TD`, `graph LR`, `graph BT`, `graph RL`, `flowchart TD`, `flowchart LR`, `flowchart BT`, `flowchart RL` |
| Sequences | `sequenceDiagram` |
| States | `stateDiagram`, `stateDiagram-v2` |

Unsupported Mermaid syntax is rejected by the parser instead of silently
rendering partial output.

## Start here

- Install from source: [Install](install.md)
- Render a diagram: [Quickstart](quickstart.md)
- See accepted Mermaid forms: [Syntax](syntax.md)
- Configure animation: [Directives](directives.md)
- Embed generated diagrams: [Embedding](embedding.md)
