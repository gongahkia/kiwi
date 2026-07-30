# ADR-0004: Explicit Incremental Compatibility Profiles

- Status: Accepted
- Date: 2026-07-30

## Context

Terminal standards and de facto behaviours are broad. Claiming general compatibility before implementing and testing it would create an unbounded project and misleading user expectations.

## Decision

Stanczyk publishes named compatibility profiles. The initial profile is `stanczyk-basic-v1`, defined in `docs/TERMINAL_COMPATIBILITY.md`.

A control sequence is considered supported only when:

- semantics are documented;
- parser and state implementation exist;
- boundary and chunking tests exist;
- known limitations are stated.

Unsupported sequences are safely ignored and exposed in debugger mode.

## Consequences

Positive:

- scope remains bounded;
- compatibility claims are testable;
- regressions can be tied to profile versions;
- users can understand why an application fails.

Negative:

- some applications will not work initially;
- profile maintenance adds documentation overhead;
- users may prefer a familiar compatibility label even when inaccurate.

## Rejected alternatives

### Claim VT100 or xterm compatibility informally

Rejected because these labels imply behaviour beyond the intended initial subset.

### Silently copy a mature emulator core

Rejected because it removes much of the learning and architectural value and may constrain the renderer/debugger design.
