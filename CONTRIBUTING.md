# Contributing to Stanczyk

## Scope

Contributions should strengthen one of the project’s declared surfaces:

- terminal parsing and state;
- recording and deterministic replay;
- sandbox or PTY backends;
- rendering and effects;
- protocol inspection;
- embedding APIs;
- tests, fixtures, documentation, and benchmarks.

Large scope additions should begin with an issue or ADR.

## Development principles

- Correctness precedes compatibility claims.
- Compatibility is added sequence by sequence with tests.
- Visual effects must not alter semantic terminal state.
- Core modules must remain usable outside the LÖVE runtime.
- External inputs are untrusted.
- Deterministic paths must not read ambient randomness or wall-clock time.
- Public formats and interfaces are versioned deliberately.

## Change categories

### Parser or state change

Include:

- sequence documentation;
- positive tests;
- boundary and malformed-input tests;
- chunk-boundary property coverage;
- golden state updates where appropriate.

### Recording change

Include:

- format or ADR update;
- backwards-compatibility assessment;
- round-trip tests;
- corruption tests;
- version-handling tests.

### Renderer or effect change

Include:

- clean-renderer regression check;
- performance impact;
- deterministic behaviour statement;
- reduced-motion behaviour for built-in animated effects.

### PTY helper change

Include:

- protocol tests;
- child cleanup tests;
- platform notes;
- failure-path tests;
- security review of new commands or payloads.

## Pull request expectations

A change should describe:

- the problem;
- the chosen approach;
- affected invariants;
- tests and benchmarks run;
- compatibility impact;
- security impact;
- follow-up work deliberately excluded.

## Commit discipline

Prefer focused commits that leave the repository passing. Avoid combining parser semantics, renderer redesign, dependency upgrades, and unrelated cleanup in one commit.

## Fixtures

Fixtures should be small, attributable when imported, and designed to isolate behaviour. Generated fixtures must record their seed and generator version.

## Compatibility claims

Do not describe Stanczyk as xterm-compatible, VT100-compatible, or compatible with a specific terminal application unless the documented profile and conformance evidence support that statement.
