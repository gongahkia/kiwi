# ADR 0013: tachyonfx Integration Depth

## Status

Accepted.

## Context

kumeyuri's TUI renderer uses `ratatui` and needs a small set of frame transition
effects between timeline keyframes. Phase 2 considered whether to wrap
`tachyonfx` or fork/customize it.

The current renderer exposes a small public enum:

```text
TuiTransitionEffect::None
TuiTransitionEffect::Fade
TuiTransitionEffect::Slide
TuiTransitionEffect::Glitch
```

The enum builds upstream `tachyonfx::Effect` values internally and keeps
tachyonfx-specific builders out of CLI options and public playback state.

## Decision

Wrap upstream `tachyonfx`; do not fork it.

`kumeyuri-render-tui` owns the stable transition enum and maps those variants to
tachyonfx effects. The CLI should continue to choose named kumeyuri transitions,
not raw tachyonfx effect graphs.

## Consequences

* The public TUI API remains small and testable.
* kumeyuri can upgrade tachyonfx without exposing its full builder surface as a
  compatibility promise.
* Advanced transition composition is intentionally out of scope until real user
  demand appears.
* If tachyonfx stops fitting, the wrapper enum provides a narrow replacement
  boundary.

## Rejected

* Fork tachyonfx: no current need for custom renderer internals, and it would add
  maintenance overhead.
* Expose tachyonfx builders directly: powerful, but it leaks dependency details
  into kumeyuri's API and CLI semantics.
* Hand-roll all effects now: lower dependency count, but duplicates tested
  transition code without evidence that tachyonfx is inadequate.
