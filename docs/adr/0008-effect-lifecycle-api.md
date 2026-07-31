# ADR-0008: Effect Lifecycle API v1

- Status: Accepted
- Date: 2026-07-31
- Amended: 2026-07-31

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
| `deterministic_random` | callback-context random facade |

Capability negotiation completes before `init`. A declared capability without its hook is valid; a hook without its capability is a typed `effect_load_error`. Capability sets do not change for an instance lifetime. Hook order follows the immutable manifest array order; ties preserve host construction order.

The host creates fresh scalar-record contexts for every callback. They contain effect ID, API version, session ID when supplied, frame sequence, integer elapsed microseconds, viewport and terminal dimensions, granted capabilities, and headless/canvas feature flags. Effects declaring `deterministic_random` additionally receive an effect-local derived seed and a fresh narrow random facade. They contain no terminal, screen, parser, backend, renderer, process, filesystem, or arbitrary host callback reference. Event and cell values are copied again per effect callback.

The host accepts an explicit unsigned-32-bit `random_seed` (default `0`). For every `deterministic_random` effect it derives an independent stream from that seed and the immutable effect ID, so manifest order and unrelated effects do not shift another effect’s sequence. The source is xorshift32 with zero replaced by the fixed non-zero seed `1831565813`; the facade provides `next_u32()` and rejection-sampled inclusive `integer(minimum, maximum)` for signed-32-bit bounds. It contains no terminal or renderer reference. This is reproducibility plumbing, not cryptographic randomness or a security boundary.

`update` receives a non-negative integer `delta_us`, bounded by the configured `max_delta_us` (default 1,000,000). The host rejects fractional, negative, and oversized values; it does not use or accumulate wall-clock seconds. Callers provide recorded/replay-derived timing. API v1 rejects rather than subdivides an oversized delta.

`on_event` receives versioned immutable records with `kind`, monotonic `sequence`, integer `timestamp_us`, and bounded schema-specific payloads. V1 kinds are `input`, `output`, `cursor`, `damage`, `screen_switch`, `scroll`, `resize`, `bell`, `title`, `mode`, `replay_seek`, `replay_reset`, and `checkpoint_restored`. A scroll payload has a direction (`up` or `down`), inclusive top and bottom rows, and a positive count no larger than that region.

The forward coordinator adapter is the v1 terminal-to-lifecycle translation point. It advances the host from each recorded backend delta after terminal mutation, slices high-volume input/output bytes at the host limit, then emits semantic records and active-screen damage ranges. `advance(delta_us)` deterministically subdivides a positive recorded delta into `update` calls no larger than `max_delta_us`; direct oversized `update` calls are still rejected. The adapter cannot seek while a host is attached: arbitrary effect-local state has no rewind or checkpoint contract. A future visual-state seek model requires a separate ADR.

`on_cell` receives a copied renderable visible cell record. The caller supplies damaged visible cells in strict row-major order; on a full redraw it supplies all renderable visible cells in the same order and the host sets `damage = true`. The host never exposes a backing grid cell.

Canvas hooks require non-headless operation and a narrow canvas facade. The facade exposes dimensions, phase, and bounded `fill_rect`, `line`, and `text` operations only. The host saves and restores the supplied graphics state around every canvas hook. Headless canvas requirements fail before `init` with typed `effect_incompatible`.

The host bounds loaded effects, callbacks per frame, event-byte payloads, canvas operations per callback, and accepted deltas. Lua effects remain trusted in-process code; this boundary is not a security sandbox.

API v1 cannot measure arbitrary Lua-retained state or execution time without adding nondeterministic host instrumentation, so it does not claim to enforce those limits. A future budget mechanism requires a separate versioned decision.

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
