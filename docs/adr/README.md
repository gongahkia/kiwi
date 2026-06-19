# Architecture Decision Records

This directory tracks non-obvious architecture decisions that affect parser
shape, renderer contracts, plugin/runtime policy, release infrastructure, or
security posture.

## Index

| ADR | Status | Decision |
| --- | --- | --- |
| [0001](0001-ast-shape.md) | Accepted | Use a typed semantic AST shared by layout, animation, and renderers |
| [0002](0002-parser-choice.md) | Accepted | Use a Rust-native parser instead of porting Mermaid's Jison grammars |
| [0010](0010-wasm-host.md) | Accepted | Use Wasmtime as the ABI 1.x WASM plugin host runtime |
| [0011](0011-svg-animation-mode.md) | Accepted | Default animated SVGs to SMIL while keeping CSS keyframes as fallback |

## Maintenance

Add or update an ADR when a change selects between credible alternatives and
the rationale would be costly to reconstruct from code alone. Use the next
zero-padded number, keep the title format `ADR NNNN: Title`, and record:

* `Status`: proposed, accepted, superseded, or rejected.
* `Context`: constraints, inputs reviewed, and relevant dates.
* `Decision`: the selected approach.
* `Consequences`: known tradeoffs and follow-up obligations.
* `Rejected`: alternatives considered and why they were not selected.

If a decision changes, keep the old ADR and mark it superseded instead of
rewriting history.
