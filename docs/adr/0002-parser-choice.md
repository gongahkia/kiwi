# ADR 0002: Parser and Token Strategy

## Status

Accepted.

## Context

Phase 1 targets Mermaid `flowchart` / `graph`, `sequenceDiagram`, and
`stateDiagram-v2`.

Inputs reviewed:

* Upstream Mermaid Jison grammars at `mermaid-js/mermaid` commit
  `be49880fbc2204fc6f4268c1f5cec791f8adc11b`.
* Current Rust parser crates on crates.io:
  * `chumsky = 1.0.0-alpha.8`
  * `logos = 0.16.1`

Upstream Mermaid grammar is not just syntax. The Jison actions mutate diagram
DBs during parsing and rely on lexer start states for strings, Markdown labels,
edge labels, flowchart shape bodies, sequence aliases, state notes, class/style
blocks, and accessibility metadata. A direct Jison port would preserve those
side effects and DB shapes, which conflicts with ADR 0001's semantic AST.

## Decision

Do not port Mermaid's Jison grammar.

Implement a Rust-native parser in `kumeyuri-core`:

1. A hand-rolled stateful lexer emits typed tokens with `Span`.
2. Diagram-specific parsers consume tokens into the ADR 0001 semantic AST.
3. Parser diagnostics preserve unsupported or recoverable constructs instead of
   silently dropping them.
4. Golden fixtures from upstream Mermaid examples and competing ASCII renderers
   define compatibility, not structural equivalence with Mermaid's Jison DBs.

Initial lexer modes:

* `Common`: diagram header, comments, directives, accessibility fields.
* `Flow`: node IDs, node shapes, subgraphs, links, edge labels, class/style,
  click/href, and shape metadata.
* `Sequence`: participants, aliases, actor config blocks, arrows, notes,
  control blocks, activation markers, autonumber.
* `State`: state IDs, composite blocks, transitions, notes, forks/joins/choice,
  class/style, click/href.

`logos` is not used for Phase 1 lexer construction because Mermaid's start-state
behavior is central, and forcing it into regex-only tokenization would move
complexity into callbacks. Re-evaluate `logos` after the hand-rolled lexer has
stable token contracts.

`chumsky` is allowed for parser combinators and recovery after the token model
stabilizes, but Phase 1 may use recursive descent where it is clearer. Do not
add `chumsky` until a concrete parser module needs it.

## Consequences

* Parser code can emit kumeyuri-native diagnostics and spans from day one.
* The AST stays renderer-independent and does not inherit Mermaid's mutable DB
  coupling.
* Compatibility work is explicit: each Mermaid grammar construct must be mapped
  into kumeyuri tokens and AST nodes.
* Initial implementation cost is higher than a mechanical Jison port.
* Future Mermaid grammar drift is handled by fixture tests plus targeted lexer
  and parser updates.

## Rejected

* Port Jison grammar and JS DB behavior directly into Rust: fastest apparent
  path, but couples parser output to Mermaid's SVG renderer model.
* Use `logos` for the full lexer immediately: attractive for simple tokens, but
  Mermaid's mode-sensitive lexing makes this premature.
* Parse source directly into renderer frames: violates the single semantic core
  required by TUI, SVG, raster, WASM, and text output.
