# ADR 0005: sparse damage with lazy full redraw

## Decision

Represent ordinary changes as a sparse set of logical cell indices, coalesce adjacent indices when consumed, and represent full redraw with one lazy flag.

## Rationale

Typing updates are naturally tiny and row updates become contiguous ranges, avoiding a native buffer write per cell. A lazy full flag avoids materializing every index for reset/resize/full-redraw workloads.

## Consequences

The renderer packs and uploads each coalesced range only, exposing changed cells, uploaded cells/bytes, range count, and full/partial state. This is intentionally simple rather than an M0 cache/eviction or region-tree system.
