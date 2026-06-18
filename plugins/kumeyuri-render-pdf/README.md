# kumeyuri-render-pdf

Reference `render-backend` plugin package for kumeyuri ABI `1.0`.

This package documents the canonical PDF backend shape:

- `kumeyuri.plugin.json` declares ABI `1.0`, kind `render-backend`, export `renderBackend = "pdf"`, and no ambient capabilities.
- `plugin.wasm` is a minimal text-format WebAssembly component placeholder for host loader tests.
- `wit/kumeyuri-plugin.wit` records the intended render-backend interface.
- `src/lib.rs` includes a deterministic minimal PDF writer used by package tests.

Install once published:

```bash
kumeyuri plugin install kumeyuri-render-pdf
```

Local validation:

```bash
cargo test --manifest-path plugins/kumeyuri-render-pdf/Cargo.toml
node scripts/test-reference-plugins.mjs
```

The full Wasmtime invocation path and production PDF rendering are tracked
separately from this reference package scaffold.
