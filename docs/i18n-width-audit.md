# I18n Width Audit

Scope: first Phase 9 pass for Unicode width dependencies and current width
callsite classification.

## Added Dependencies

- `unicode-width`: display-cell width for strings and grapheme clusters.
- `unicode-segmentation`: grapheme boundaries for safe label wrapping.

The core exposes `kumeyuri_core::unicode` helpers:

- `display_width`;
- `display_width_i32`;
- `truncate_display_width`;
- `wrap_display_width_lines`.

## Updated Paths

- Flowchart node sizing now uses display-cell width through `label_width` and
  `label_metrics`.
- `--max-label-width` wrapping now compares display width and splits long words
  on grapheme boundaries.
- Layout sizing now has no direct `.chars().count()` width callsites in
  `crates/kumeyuri-core/src/layout.rs`.

## Remaining Width Paths

`rg` shows direct `.chars().count()` width calculations remain in these areas:

| Area | Current use | Follow-up |
| --- | --- | --- |
| `crates/kumeyuri-core/src/frame.rs` | Centering, label positioning, and text writes into the glyph grid. | Migrate after BiDi and CJK cell occupancy rules are defined. |
| `crates/kumeyuri-core/src/animator.rs` | Marker regions derived from positioned labels. | Migrate after layout/frame width semantics match. |
| `crates/kumeyuri-cli/src/main.rs` and `crates/kumeyuri-render-wasm/src/lib.rs` | ASCII-only fixed-width assertions in tests. | Keep unless tests add non-ASCII fixtures. |

Frame output is still char-cell based. This pass does not claim full CJK,
emoji, or BiDi rendering support.
