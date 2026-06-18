# Regex Audit

Last audited: 2026-06-18.

## Rust

- No workspace runtime crate depends on `regex`, `fancy-regex`, PCRE, or Oniguruma.
- `regex-syntax` appears in `Cargo.lock` only through the dev dependency `proptest`.
- Parser and renderer code use hand-written scanners for Mermaid grammar rather than regex tokenizers.

## JavaScript

Runtime regexes were removed from:

- `render-action/render.mjs` glob matching
- `packages/rehype-kumeyuri/index.js` class splitting
- `scripts/check-compat-doc-versions.mjs`
- `scripts/check-coverage-snapshot-delta.mjs`
- `scripts/check-mermaid-coverage.mjs`
- `scripts/verify-svg-sanitizer.mjs`
- `editors/vscode/webview.js`
- `editors/opencode/kumeyuri-render/scripts/render-mermaid-blocks.mjs`
- `editors/claude-code/kumeyuri-render/skills/kumeyuri-render/scripts/render-mermaid-blocks.mjs`

Remaining regex references are intentionally outside user-input runtime parsing:

- Tests use `assert.match` and `assert.throws` for fixed expected output/error checks.
- `editors/vscode/media/kumeyuri_render_wasm.js` is generated wasm-bindgen glue and uses a bounded object tag extraction helper.
- `editors/opencode/kumeyuri-render/bun.lock` records the transitive package `shebang-regex` from tooling metadata.

## Re-Audit Commands

```sh
rg -n "regex|Regex|RegExp|match\\(|matchAll\\(|split\\(/|replace\\(/|assert\\.match|assert\\.throws|/[^/]+/[a-z]*" packages scripts editors render-action -g '*.js' -g '*.mjs'
rg -n "name = \"regex\"|name = \"regex-syntax\"|fancy-regex|pcre|onig|oniguruma" Cargo.lock Cargo.toml crates companion plugins
```
