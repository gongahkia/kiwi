# Migrating from mermaid-ascii

This guide covers the Go `mermaid-ascii` CLI lineage used by the vendored
`tests/golden/mermaid-ascii` fixtures and the comparison adapters for
`AlexanderGrooff/mermaid-ascii` and `pgavlin/mermaid-ascii`.

## Main differences

| Area | mermaid-ascii | kumeyuri |
| --- | --- | --- |
| Runtime | Go CLI | Rust CLI/crates plus WASM wrapper |
| Typical command | `mermaid-ascii --file input.mmd --ascii` | `kumeyuri render input.mmd --format text` |
| Output focus | Static terminal text | Static text plus animated TUI, SVG, raster, WASM |
| Diagram coverage | Flowchart-oriented fixtures in the vendored corpus | See `COVERAGE.md` for current root support |
| Themes | Terminal glyph output | Built-in themes and charset selection |

## Command replacement

Before:

```sh
mermaid-ascii --file diagram.mmd --ascii > diagram.txt
```

After:

```sh
kumeyuri render diagram.mmd --format text --charset ascii > diagram.txt
```

Use Unicode output when box-drawing glyphs are acceptable:

```sh
kumeyuri render diagram.mmd --format text --charset unicode > diagram.txt
```

## Animation and richer exports

mermaid-ascii emits one static text artifact. kumeyuri can keep the same source
and render additional surfaces:

```sh
kumeyuri play diagram.mmd --loop
kumeyuri render diagram.mmd --format svg --theme github > diagram.svg
kumeyuri render diagram.mmd --format gif --padding 12 > diagram.gif
```

Use `play` for local terminal review and SVG/GIF/APNG/WebP for publishing.

## CI migration

Replace CLI invocations in scripts with `kumeyuri render`:

```sh
for file in diagrams/*.mmd; do
  out="rendered/$(basename "$file" .mmd).txt"
  kumeyuri render "$file" --format text --charset ascii > "$out"
done
```

If the CI job currently diffs `mermaid-ascii` text output byte-for-byte, expect
layout differences on multi-layer graphs. Keep those diffs visible and review
them before replacing golden files.

## Comparison harness

The repo keeps adapters for both known `mermaid-ascii` binaries:

```sh
MERMAID_ASCII_BIN=/path/to/mermaid-ascii \
  npm run bench:compare:alexander-mermaid-ascii

PGAVLIN_MERMAID_ASCII_BIN=/path/to/mermaid-ascii \
  npm run bench:compare:pgavlin-mermaid-ascii
```

Regenerate the static comparison page:

```sh
scripts/generate-static-comparison.sh
```

The generated page labels parity losses instead of hiding mismatches.

## Fixture migration

Vendored `mermaid-ascii` fixtures live under:

```text
tests/golden/mermaid-ascii/testdata
```

Do not edit vendored outputs in place. If upstream fixtures are refreshed,
replace the copied subtree and update `tests/golden/corpora.toml` with the new
upstream commit.

## When not to migrate

Keep `mermaid-ascii` in a benchmark matrix if you need a long-lived external
baseline. Migrate production rendering to kumeyuri when you need animated
terminal playback, SVG/raster exports, WASM embeds, or the broader compatibility
matrix tracked in `COVERAGE.md`.
