# ADR 0011: direct print sink with action test boundary

## Context

M1 represented every parser output, including each printable codepoint, as a Lua table before `State` applied it. LuaJIT profiling of printable output found the terminal-state path hot enough that this transient allocation and callback dispatch were worth removing, while parser conformance tests rely on inspecting semantic action tables.

## Decision

`Parser.new` continues to accept the action callback used by parser tests, replay fixtures, and state-only benchmarks. It may also receive a `State`-shaped sink. In sink mode only decoded print codepoints call `State:write_codepoint` directly; execute, ESC, CSI, OSC, and ignored sequences still use the action path and `State:apply`.

## Consequences

The live and replay paths avoid a print action allocation per glyph without folding terminal semantics into the parser or exposing parser internals to the renderer. The dual entry point is deliberately narrow and has snapshot-equivalence coverage. A generic event bus or a parser rewrite was rejected because it would expand M1's semantic surface without evidence of need.
