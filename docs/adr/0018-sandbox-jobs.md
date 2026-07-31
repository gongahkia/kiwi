# ADR-0018: Deterministic sandbox jobs

- Status: Accepted
- Date: 2026-07-31

## Context

Sandbox commands need delayed application work without importing wall-clock timing,
threads, yielding, host timers, or a second output transport.

## Decision

Each sandbox session owns an in-memory scheduler with logical time initially at zero.
Only `session:advance(delta_us)` changes that time. `delta_us` is a bounded,
non-negative integer microsecond count; zero drains already-due work. Time arithmetic,
delays, job count, callback work, callback metadata, callback count per advance, and
zero-delay chaining are bounded before mutation. No scheduler code reads host time.

API v1 supports one-shot jobs only. A command declares `jobs.schedule` and must receive
the same immutable grant from its session before it receives `context.jobs`. That
expiring facade has `schedule(delay_us, callback)`, `cancel(job_id)`, and
`is_pending(job_id)`. It neither exposes the scheduler nor accepts arbitrary host or
session callbacks. A job has a deterministic session-local ID and insertion sequence;
it runs by ascending `(due_us, insertion_sequence)`. A zero-delay job never runs from
`schedule`; if a callback schedules one, it follows jobs already queued for that due
time. A callback limit stops one advance with due work retained for a later
`advance(0)`.

Jobs belong to their creating command invocation. Scheduling retains bounded invocation
work, so normal handler return does not settle that invocation until every owned job is
completed, failed, or cancelled and the existing output FIFO drains. Callback contexts
are fresh immutable values containing job ID, due time, logical time, execution
sequence, the invocation writer, and only the capability-gated VFS and scheduler
facades retained at scheduling time. They expose no session, registry, terminal,
renderer, backend, process, VFS node, or another session.

A pending job is removed before its callback executes. It completes, fails once, or is
cancelled before execution. Callback failure is a typed `callback_failure`, fails its
own invocation, preserves accepted output, cancels that invocation's remaining pending
jobs, and does not retry or disturb other invocations. `cancel(job_id)` returns
`{ cancelled = true }` once and `{ cancelled = false }` thereafter or for an unknown
completed/cancelled ID. Invocation cancellation cancels all of its pending jobs and
preserves already queued output under ADR-0013. Recursive same-session advance returns
`scheduler_reentrant` without state change. Session destruction cancels and releases
all jobs.

Job callbacks enqueue bytes only through the invocation writer. Later FIFO polling
creates the existing zero-time output events (`delta_us = 0`); logical due time controls
availability only. Jobs, IDs, pending callbacks, host delays, and scheduler diagnostics
are absent from terminal semantics, recordings, and checkpoints.

Stable scheduler reasons include `invalid_delta_us`, `advance_too_large`,
`logical_time_overflow`, `invalid_delay`, `delay_too_large`, `scheduler_full`,
`scheduling_closed`, `unknown_job`, `callback_failure`, `scheduler_reentrant`,
`resource_limit`, and `cancelled`.

## Consequences

Equal commands, grants, limits, scheduling calls, cancellations, and explicit advances
produce equal IDs, callback order, failures, and queued output. Periodic work is
explicit rescheduling. Host-clock timers, periodic timers, cron/calendar syntax,
threads, sleeping, futures, coroutine suspension, job persistence, and scheduler replay
require a separate decision.
