# ADR 0008: row indirection and bounded primary scrollback

## Decision

Represent each screen as mutable row objects and use a fixed-capacity ring for primary scrollback. Scroll by moving row references, not by rebuilding every cell.

## Rationale

The M0 synthetic scrolling workload exposed costly Lua table/cell reconstruction. Real terminal scrolling needs a representation whose normal path is row-oriented while preserving existing structured cells and damage ranges.

## Consequences

Only entering blank rows are allocated during normal scroll. Full-screen primary upward scroll offers outgoing rows to scrollback; margins and alternate screens do not. History navigation is deterministic and memory remains bounded by the configured line count.
