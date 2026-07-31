# ADR-0007: Effect Manifest API v1

- Status: Accepted
- Date: 2026-07-31

## Context

Effects are a public extension boundary. Their manifests must be validated before hooks or renderer resources are loaded, remain serialisable for replay and hot reload, and identify whether a visual result is deterministic.

## Decision

Effect Manifest API v1 requires exactly these fields:

- `id`: non-empty effect identifier;
- `version`: canonical stable SemVer `major.minor.patch`;
- `api_version`: integer `1`;
- `determinism`: `static`, `deterministic`, or `interactive`;
- `capabilities`: a dense, duplicate-free array from the API v1 capability allowlist;
- `parameters`: a map of typed parameter schemas.

API v1 capabilities are `terminal_events`, `cell_transform`, `row_transform`, `draw_before`, `draw_after`, `post_process`, `persistent_canvas`, and `interactive_time`. `interactive_time` is valid only for manifests whose determinism is `interactive`.

Parameters have a serialisable default and are one of: `number` with optional finite `min` and `max`; `integer` with optional integer `min` and `max`; `boolean`; `string` with optional bounded `max_length`; or `enum` with a dense list of string, boolean, or finite numeric values. Unknown fields, duplicate capabilities, invalid bounds, and unsupported API versions fail with typed `effect_load_error` values before effect construction.

Manifests are normalised into effect-owned tables. Callers receive copies and cannot mutate the accepted definition through their input table or a manifest accessor.

Incompatible manifest changes require a new API version and ADR. Additive capabilities or parameter schema fields require explicit versioned review.

## Consequences

Positive:

- effect loading is deterministic and auditable;
- future parameter serialisation has a bounded scalar vocabulary;
- hook dispatch can rely on declared capabilities;
- interactive effects are visibly separated from deterministic export candidates.

Negative:

- experimental effects must conform to a stricter initial schema;
- unsupported future fields are rejected until versioned support is added.

## Rejected alternatives

### Free-form Lua manifests

Rejected because manifests could not be safely validated, serialised, or compared across replay runs.

### Boolean deterministic flag only

Rejected because `static`, deterministic time-driven, and interactive wall-time effects have materially different export behaviour.

### Implicit capabilities inferred from hooks

Rejected because loading would execute unvalidated plugin code and conceal resource or timing intent.
