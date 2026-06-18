# Hacker News launch draft

## Title

Show HN: Kumeyuri - animated Mermaid diagrams for terminals, SVGs, GIFs, and WASM

## First comment

Hi HN, I built Kumeyuri because Mermaid is great for writing system diagrams in
plain text, but motion usually forces you into a renderer-specific toolchain.

The implementation is Rust-first. Source parses into a semantic AST for the
supported Mermaid families, then layout produces stable coordinates and the
animator lowers supported animated roots into a deterministic frame stream. The
renderers consume that same frame stream for terminal text/TUI playback,
animated SVG, GIF/APNG/WebP, and a wasm-bindgen browser renderer.

The interesting constraint is that SVG is not the center of the design. It is
one backend. That makes the same `.mmd` file usable in a terminal demo, a GitHub
README, a static docs site, a slide deck fallback, or a web component.

Current pieces in the repo:

- CLI: `render`, `watch`, and `play`
- Outputs: text, SVG, GIF, APNG, WebP, TUI
- Web: typed TS wrapper and `<kumeyuri-diagram>` custom element
- Compatibility: 11 animated partial Mermaid families, 17 static-only partial
  families, and 3 known unsupported upstream roots tracked in `COVERAGE.md`
- Tests: parser fixtures, static snapshots, animation hash snapshots, SVG
  sanitizer check, raster snapshots, Playwright browser coverage, fuzz/negative
  fixtures, compat drift checks, and WASM gzip budget

The important caveat is that support is partial. The compatibility matrix is
explicit about what is parser-only, static-only, animated, rejected, or
schematic rather than full Mermaid visual parity.

Repo: https://github.com/gongahkia/kumeyuri

Launch post source: `site/blog/launch.html`
