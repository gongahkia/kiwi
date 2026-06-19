# ADR 0018: Keep The Native Flow Layout Engine

Status: Accepted

Date: 2026-06-19

## Context

Phase 1 left one open decision: keep kumeyuri's layered Sugiyama-style flow
layout implementation or wrap `layout-rs`.

`layout-rs` is a Rust Graphviz/DOT layout library and command-line renderer.
Its public docs describe support for parsing/rendering Graphviz files and a
programmatic `VisualGraph` API.

## Measurement

Command:

```sh
cargo bench -p kumeyuri-core --bench layout_engine_compare -- --sample-size 10
```

Benchmark input: generated 100-node binary-tree flowchart, rendered as Mermaid
for kumeyuri and as an equivalent programmatic graph for `layout-rs`.

Observed on 2026-06-19:

| Engine | Criterion mean |
| --- | ---: |
| kumeyuri native Sugiyama-style flow layout | 6.5679 ms |
| `layout-rs` `VisualGraph` layout + SVG finalize | 305.76 ms |

## Decision

Keep the native flow layout engine.

## Consequences

- kumeyuri stays dependency-light in runtime code; `layout-rs` remains a
  dev-only benchmark comparison.
- The native engine remains tuned for terminal/text frame geometry instead of
  Graphviz-compatible SVG geometry.
- Revisit only if a future graph class needs Graphviz semantics that outweigh
  the measured speed and geometry-fit gap.
