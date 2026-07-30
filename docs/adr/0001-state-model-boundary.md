# ADR-0001: Separate Terminal Semantics from Backends and Rendering

- Status: Accepted
- Date: 2026-07-30

## Context

Stanczyk must support replay, sandbox, and PTY inputs while also enabling programmable visual effects. A monolithic terminal object tied to LÖVE would make correctness testing difficult and would allow visual features to distort semantic behaviour.

## Decision

The terminal parser and semantic state are implemented as plain Lua modules with no dependency on `love.*`, filesystems, subprocesses, or wall-clock APIs.

Backends emit normalised ordered events. The coordinator applies those events to the terminal. Renderers and effects consume read-only state and semantic events after mutation.

Effects cannot mutate terminal state.

## Consequences

Positive:

- core tests run without graphics;
- all backends exercise the same parser;
- replay equivalence is straightforward;
- effects remain replaceable;
- embedding multiple terminals is practical.

Negative:

- interfaces and event structures require up-front design;
- some optimisations need explicit snapshot and damage boundaries;
- shortcuts that directly update rendering from parser actions are prohibited.

## Rejected alternatives

### Monolithic LÖVE terminal object

Rejected because it couples parser correctness, I/O, timing, and GPU state.

### Separate parser implementations per backend

Rejected because replay, sandbox, and PTY behaviour would diverge.
