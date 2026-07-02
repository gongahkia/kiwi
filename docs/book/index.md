# kumeyuri

kumeyuri renders Mermaid diagrams as animated text artifacts.

These docs describe the current source tree. Crates.io, npm, and CDN publish
tasks are tracked in GitHub issues, so install and embed examples use local
source builds or generated assets.

## What it renders

| Surface | Output |
| --- | --- |
| Terminal | Static text and interactive TUI playback |
| SVG | Animated SVG with frame groups, SMIL, CSS fallback, and text metadata |
| Raster | GIF, APNG, and WebP animation outputs |
| Browser | WASM renderer plus typed TypeScript API and `<kumeyuri-diagram>` custom element |

## Supported Mermaid families

The current compatibility surface tracks Mermaid docs `11.15.0`: 11 animated
partial families, 20 static-only partial families, and no unsupported tracked
roots. Run `kumeyuri compat`, inspect `site/parity.json`, or read
`docs/compat.md` before making release or parity claims.

Partial support means kumeyuri parses and renders the root, but does not promise
drop-in Mermaid.js visual/config parity. Static-only support means rendering
works and playback collapses to one frame.

## Start here

- Install from source: [Install](install.md)
- Render a diagram: [Quickstart](quickstart.md)
- See accepted Mermaid forms: [Syntax](syntax.md)
- Configure animation: [Directives](directives.md)
- Embed generated diagrams: [Embedding](embedding.md)
- Check parity evidence: [Compatibility Dashboard](compat-dashboard.md)
- Audit a migration: [Migration Audit](migration-audit.md)
- Wire a static site: [Static Site Recipes](static-site-recipes.md)
