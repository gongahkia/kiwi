# ADR-0019: Sandbox backend authority boundary

- Status: Accepted
- Date: 2026-07-31

## Context

The command modules need an actual backend path that reaches the terminal only through
normalised events, while keeping sandbox mode distinct from the future PTY backend.

## Decision

`backend.sandbox` owns one `shell.session` and implements the standard backend methods.
It accepts a complete submitted command-line byte string through `send_input(bytes)`;
line editing, echo, prompt rendering, shell parsing, and host context injection are not
part of that call. Dispatch uses the registry, strict tokenizer, history admission,
capability negotiation, per-session VFS, command output FIFO, completion, and jobs
facades already defined by their ADRs. Built-ins are registered normally in the supplied
registry; the backend has no parser branch for them.

`poll(delta_us)` calls only `session:advance(delta_us)`, then drains bounded command
output FIFOs in deterministic invocation order. Drained bytes are returned as their
existing zero-time output events. Polling has a bounded event result; active invocations
and queued resize events are bounded and reject further work with typed resource-limit
errors before command dispatch or queue mutation. `resize` queues a normalised zero-time
resize event. Completion and history are narrow session wrappers. Stop cancels active
invocations, destroys the session, clears backend-owned queues, and cannot restart.

The implementation has no public operation for process spawn, shell execution, host
filesystem access, mounts, environment access, native loading, network access, PTY
helpers, or LÖVE system launch. Built-ins only use their declared VFS facades and output
writer. This is public-API authority isolation, not hostile-code containment: registered
Lua callbacks are trusted in-process code and can access Lua globals unless a future
restricted Lua environment loads them.

## Consequences

Sandbox terminal mutations arrive only through polled normalised output/resize events;
the backend itself never modifies terminal state. The sandbox path is portable without
native helpers and remains distinct from explicit PTY selection. Restricted Lua loading,
host-domain event capabilities, interactive line editing, input-event recording policy,
and automatic command discovery require separate decisions.
