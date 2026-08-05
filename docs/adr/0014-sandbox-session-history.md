# ADR-0014: Session-local sandbox command history

- Status: Accepted
- Date: 2026-07-31

## Context

Sandbox users need local command recall without turning convenience state into a
recording field, shared mutable singleton, or persistent configuration schema.

## Decision

Each `shell.session` owns one in-memory, byte-oriented FIFO history. It is independent
of every other session and is cleared by `reset_history()` or idempotent `destroy()`.
History is not saved, mounted, recorded, checkpointed, or reconstructed from recordings.

The default immutable bounds are 128 entries, 32,768 retained bytes, and 4,096 bytes per
entry. Hosts may lower but not raise them. Setting both entry and retained-byte capacity
to zero explicitly disables history; zero for only one of those capacities is invalid.
When a valid new entry would exceed count or byte capacity, the buffer evicts the minimum
number of oldest entries needed to fit it. Oversized entries are retained neither fully
nor partially and return bounded typed diagnostics without preventing dispatch.

The session adds the exact submitted byte string only after strict tokenization succeeds
and produces at least one argument. It then dispatches normally. Therefore delimiter-only
and tokenizer-invalid input are absent; known commands, unknown commands, callback
failures, cancellations, duplicates, NUL, and invalid UTF-8 are retained exactly when
within bounds. History has one-based oldest-first indexing. `get` and bounded `list`
return values detached from collection ownership, and `clear` affects nothing outside the
history object.

## Consequences

History is a non-semantic session convenience. It cannot change terminal output,
recordings, checkpoints, registry contents, active invocations, or terminal state. UI
navigation is deliberately separate from the retained data model and needs its own
cursor object if introduced later.
