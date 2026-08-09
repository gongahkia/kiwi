# ADR 0013: pinned Unicode text semantics

## Context

M1 retained decoded UTF-8 strings per terminal cell but did not define grapheme boundaries or terminal width. Delegating either to the host would make parser chunking, replay, and width behavior dependent on libc/locale/version drift. Allowing arbitrary combining streams to grow an unbounded cell would also make the terminal state an unbounded resource sink.

## Decision

Kiwi checks in official Unicode 17.0.0 source files and SHA-256 hashes, generates flat property tables deterministically, and validates every checked-in GraphemeBreakTest case. The state retains raw code points, implements UAX #29 EGC boundaries incrementally, caps one cluster at 64 code points, and uses a versioned terminal-only width policy. EAW A and private-use default to one cell; documented emoji sequences and EAW W/F use two. Width is never inferred from font advances.

## Consequences

Replay is deterministic across hosts with different Unicode/libc versions and arbitrary PTY chunking. The cap visibly splits pathological clusters and records a counter instead of allocating indefinitely. Width policy changes require a new terminal session rather than attempting unsafe live reflow. This ADR does not define bidi, line breaking, normalization, or a host-compatibility promise.
