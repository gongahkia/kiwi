# ADR-0011: Host-coordinated effect replacement

- Status: Accepted
- Date: 2026-07-31

## Context

Development loaders need to update an effect without exposing a partly constructed
instance, granting renderer privileges, or changing terminal semantic recordings.

## Decision

The effect host exposes `replace(effect_id, candidate)`. A development loader is
responsible for watching files and constructing the candidate with the existing
public effect API; the core does not watch, compile source, or discover modules.

Replacement is permitted only at a quiescent host frame boundary: no effect callback,
canvas frame, or visual frame is active. The candidate is manifest-validated,
capability-negotiated, parameter-migrated, and initialised off-chain before its slot is
swapped. The logical id, chain position, enabled state, and reload generation are
preserved. Candidate capabilities must be a subset of the capabilities negotiated by
the active host, so renderer resources are never reconfigured by a preset.

Parameters migrate only when their name and declared type match and the old value
validates against the candidate declaration. Other values use candidate defaults and
produce bounded diagnostics. No type coercion occurs. The replacement gets new local
state and a fresh deterministic RNG stream derived from the host seed and logical id.

After the atomic slot swap the host calls the old instance's `shutdown` once. A failed
candidate validation, configuration, or `init` retains the old instance. A failed old
`shutdown` is isolated and does not roll back the successful swap. Hooks and events
only see either the old or fully initialised candidate.

Reload commands do not mutate terminal state or terminal semantic recordings. A host
may separately retain a visual-session trace outside that stream. Given equal requests,
seeds, event streams, and frame boundaries, replacement lifecycle ordering is
deterministic.

## Consequences

Reloading is explicit and host-coordinated. API v1 intentionally does not migrate Lua
tables, closures, coroutines, shader objects, or other opaque local state. Explicit
subscriptions are reconstructed from the candidate manifest and hooks; subscriptions
which are no longer declared are absent after the swap.
