# ADR-0008: Effect Lifecycle API v1

- Status: Accepted
- Date: 2026-07-31

## Context

Effects need deterministic observations of terminal activity and narrow rendering hooks without receiving mutable terminal, parser, backend, or renderer state. The lifecycle boundary must remain safe for headless replay and isolate failures from semantic processing.

## Decision

Lifecycle API v1 uses optional hooks gated by immutable manifest capabilities:

| Capability | Hook |
| --- | --- |
| `lifecycle` | `init`, `shutdown` |
| `terminal_events` | `on_event` |
| `cell_observation` | `on_cell` |
| `canvas_before` | `before_canvas` |
| `canvas_after` | `after_canvas` |
| `frame_update` | `update` |

Capability negotiation completes before `init`. A declared capability without its hook is valid; a hook without its capability is a typed `effect_load_error`. Capability sets do not change for an instance lifetime. Hook order follows the immutable manifest array order; ties preserve host construction order.

The host creates fresh scalar-record contexts for every callback. They contain effect ID, API version, session ID when supplied, frame sequence, integer elapsed microseconds, viewport and terminal dimensions, granted capabilities, and headless/canvas feature flags. They contain no terminal, screen, parser, backend, renderer, process, filesystem, or arbitrary host callback reference. Event and cell values are copied again per effect callback.

`update` receives a non-negative integer `delta_us`, bounded by the configured `max_delta_us` (default 1,000,000). The host rejects fractional, negative, and oversized values; it does not use or accumulate wall-clock seconds. Callers provide recorded/replay-derived timing. API v1 rejects rather than subdivides an oversized delta.

`on_event` receives versioned immutable records with `kind`, monotonic `sequence`, integer `timestamp_us`, and bounded schema-specific payloads. V1 kinds are `input`, `output`, `cursor`, `damage`, `screen_switch`, `resize`, `bell`, `title`, `mode`, `replay_seek`, `replay_reset`, and `checkpoint_restored`.

`on_cell` receives a copied renderable visible cell record. The caller supplies damaged visible cells in strict row-major order; on a full redraw it supplies all renderable visible cells in the same order and the host sets `damage = true`. The host never exposes a backing grid cell.

Canvas hooks require non-headless operation and a narrow canvas facade. The facade exposes dimensions, phase, and bounded `fill_rect`, `line`, and `text` operations only. The host saves and restores the supplied graphics state around every canvas hook. Headless canvas requirements fail before `init` with typed `effect_incompatible`.

The host bounds loaded effects, callbacks per frame, event-byte payloads, canvas operations per callback, and accepted deltas. Lua effects remain trusted in-process code; this boundary is not a security sandbox.

Hook exceptions, invalid returns, and canvas state failures produce diagnostics, disable only the failing effect, attempt `shutdown` exactly once after successful initialization, and do not roll back or alter terminal semantics.

## Consequences

Positive:

- deterministic replay can produce stable lifecycle ordering and timings;
- headless replay rejects incompatible visual effects early;
- effects cannot mutate engine semantic objects through lifecycle inputs;
- canvas state cannot leak across effect callbacks.

Negative:

- callers must explicitly translate accepted terminal activity into lifecycle records;
- direct rich terminal queries require a future narrow-snapshot ADR;
- trusted Lua callbacks can still consume host CPU outside a separately sandboxed runtime.

## Rejected alternatives

### Passing terminal and renderer objects to hooks

Rejected because it permits semantic mutation, hidden reads, and renderer-state leakage.

### Float-second update timing

Rejected because accumulated wall-clock values make deterministic replay and export ambiguous.

### Unguarded canvas hooks

Rejected because one effect could leak graphics state into later effects or the base renderer.
