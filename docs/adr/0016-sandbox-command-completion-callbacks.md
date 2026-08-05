# ADR-0016: Sandboxed command completion callbacks

- Status: Accepted
- Date: 2026-07-31

## Context

Registry-name completion cannot describe command-specific argument vocabularies. A
callback extension must not gain command-execution authority or bypass completion bounds.

## Decision

When the scanner cursor is after an exactly registered first argument, a command may
provide a validated `complete(request)` callback. The optional registry `completion`
capability records an intent to provide this callback; declaring it without a callback
is a typed `unknown_completion_capability` failure. A command with neither has no
command-specific candidates.

The callback receives one immutable, bounded request: command name; detached completed
arguments/count; active argument index and decoded prefix; original line bytes; cursor;
replacement span; quote mode; and pending-escape state. It has no terminal, parser,
renderer, process, registry, output writer, invocation, environment, filesystem, host
callback, or session object. It runs synchronously and may return a dense ordered list
of logical strings or candidate records. Callback order is preserved.

Candidate records use `value` and optional display, description, category, sort key, and
replacement range. The engine validates the dense return list, exact fields, string and
byte bounds, all range offsets, total candidate bytes, and candidate count before exposing
anything. It generates the canonical Stanczyk double-quoted insertion from each logical
value. Exact duplicate complete candidates are removed; candidates with distinct metadata
or ranges remain. No partial validated result is returned on an error.

Callback exceptions return `callback_failure`; malformed lists return
`invalid_callback_return`; malformed ranges return `invalid_replacement_range`; count
and byte failures use `too_many_candidates` and `candidate_too_large`. Completion is
non-reentrant: nested calls cause `reentrant_completion_call`, including the outer call,
and later calls remain usable. A completion failure does not mutate or disable the
underlying command handler, history, output, terminal state, recordings, or registry.

## Consequences

Command-specific completion remains synchronous, byte-oriented, bounded, and
deterministic for equal request inputs and callback behavior. Async, subprocess,
filesystem, environment, network, timed, and resumable completion remain excluded until
a separate owner decision.
