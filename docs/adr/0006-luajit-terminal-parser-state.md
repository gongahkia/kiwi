# ADR 0006: LuaJIT-owned streaming terminal parser and state

## Decision

Implement Kiwi's M1 parser and terminal state in LuaJIT. The parser emits semantic action tables; state mutation is a separate LuaJIT layer. Do not embed libvterm, libghostty-vt, or another terminal emulator core.

## Rationale

Kiwi needs an inspectable behavioral contract and renderer-facing state that can evolve with its research goals. The action boundary makes arbitrary byte chunking, malformed input, and sequence recognition testable without coupling to screen mutation or GPU code. The bounded xterm-style subset is sufficient for M1 without claiming full compatibility.

## Consequences

Terminal behavior follows current xterm/ECMA-48/terminfo sources where M1 implements it. Parser parameters, intermediates, and strings are bounded; unknown behavior is recorded structurally. Compatibility breadth remains an explicit future decision rather than an imported library's opaque behavior.
