# ADR-0013: Sandboxed command output backpressure

- Status: Accepted
- Date: 2026-07-31

## Context

Sandbox commands must emit incremental terminal bytes without writing terminal state
during a handler, depending on host timing, or accumulating unbounded output.

## Decision

Every dispatched command owns one private, byte-oriented FIFO output invocation. A
command receives its writer as the third `run(context, argv, writer)` callback argument
and calls `writer:emit(bytes)`. Emit copies the supplied Lua byte string before it is
retained, appends one complete logical chunk, and never blocks, yields, renders, records,
mutates terminal state, or invokes host callbacks. Empty writes are successful no-ops.

The immutable per-invocation defaults are 16,384 bytes per write, 65,536 queued bytes,
64 queued chunks, 16,384 drained bytes per poll, and 16 output events per poll. Hosts
may tighten, but not raise, them. Zero and negative limits are invalid.

An emit that exceeds the per-write bound returns `sandbox_command_error` with
`detail.reason = "emit_too_large"`; byte or chunk capacity exhaustion returns
`"output_overflow"`. Both leave the attempted write entirely absent and latch an
`output_overflow` invocation failure. Later writes return `"output_closed"`. Previously
accepted bytes remain queued and drainable. Output is never dropped, truncated,
overwritten, expanded, or blocked for capacity.

`invocation:poll({ max_bytes?, max_events? })` drains the FIFO head only. It validates
requested limits before changing queue state, coalesces the maximal leading byte prefix
into the fewest events possible, and splits only the head chunk when its remaining
suffix exceeds `max_bytes`. API v1 has one output channel, so each non-empty poll
produces one coalesced event and therefore always respects the event bound. Every event
is `runtime.event.output(data, 0, source_sequence)`: it has `delta_us = 0`, receives its
monotonic sequence at poll time, and has no wall-clock timestamp. A dispatcher owns one
sequence source, so command invocations from it receive monotonic source sequences in
host poll order.

Execution and drainage are independent. Status reports execution state, queued bytes
and chunks, failure, and settlement: a finished or failed command can retain drainable
bytes, and is settled only after execution stops and the queue empties. Cancellation
closes the writer, exposes a typed `cancelled` state, preserves queued bytes, and lets
the host drain them. `release()` is idempotent after settlement and releases queue
storage. Callback failures also preserve already queued bytes.

Only events returned by polling enter the terminal/recording event path. Queued,
rejected, overflowed, and diagnostics bytes are not terminal output. API v1 excludes
blocking writes, threads, implicit yields, producer wakeups, resumable coroutines,
timed output, and fairness guarantees between invocations.

Stable output reasons are `output_overflow`, `output_closed`, `emit_too_large`,
`invalid_poll_limit`, `output_resource_limit`, and `cancelled`.
`output_resource_limit` covers exhausted event-sequence resources or a release request
before settlement; it does not drain or reorder bytes.

## Consequences

Equal command writes, limits, poll calls, and dispatcher order produce equal output
bytes and event sequences regardless of host delays or thread scheduling. A future
timed-command or resumable producer design requires a separate owner decision.
