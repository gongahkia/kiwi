# ADR 0019: advisory per-pass budgets

## Status

Accepted for M3.

## Decision

Kiwi accepts optional per-pass budget metadata with positive `cpu_ms`,
`gpu_ticks`, or `cadence_hz` fields, non-negative integer
`allocation_bytes`, and a `window` from 1 through 120 (default 30). Budget accounting
is opt-in through `KIWI_PASS_BUDGETS=1`; it enables the existing per-pass CPU
metrics internally without requiring the separate diagnostics flag.

For each declared dimension, Kiwi retains only the rolling window and compares
its arithmetic mean with the declared limit. It exposes plain pass status and
bounded warnings (at most 64) with pass identity, dimension, sample, average,
limit, frame, and window. Over-budget is advisory: Kiwi neither sleeps, skips a pass, nor
changes terminal output.

GPU ticks are recorded only for new completed timestamp samples. CPU and
cadence accounting continue when timestamps are disabled, unsupported, or
pending. API v1 has no extension-owned GPU allocation capability or memory
query, so allocation accounting is explicitly unavailable instead of an
estimate. This keeps the metadata forward-compatible without implying a
measurement that Kiwi cannot make.

## Consequences

Extensions receive copied declared metadata in `context.pass.budget` and
the latest plain status in `context.budget`. They may reduce optional work or
request a slower animation after a warning, but must preserve terminal
semantics. Inspector and top-level diagnostics present the same bounded data.

## Validation evidence

`make budget-smoke` runs a local semantic observer with deliberately tiny CPU
and cadence limits. It produced structured warnings for that extension while
the core background, glyph, and cursor passes continued to render.
