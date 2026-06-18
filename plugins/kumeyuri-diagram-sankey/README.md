# kumeyuri-diagram-sankey

Reference `diagram-type` plugin package for kumeyuri ABI `1.0`.

This package documents the canonical custom diagram type shape:

- `kumeyuri.plugin.json` declares ABI `1.0`, kind `diagram-type`, export `diagramType = "sankey"`, and no ambient capabilities.
- `plugin.wasm` is a minimal text-format WebAssembly component placeholder for host loader tests.
- `wit/kumeyuri-plugin.wit` records the intended diagram-type interface.
- `src/lib.rs` includes a deterministic Sankey CSV parser and frame lowerer used by package tests.

Install once published:

```bash
kumeyuri plugin install kumeyuri-diagram-sankey
```

Local validation:

```bash
cargo test --manifest-path plugins/kumeyuri-diagram-sankey/Cargo.toml
node scripts/test-reference-plugins.mjs
```

The full Wasmtime invocation path and host registration smoke tests are tracked
separately from this reference package scaffold.
