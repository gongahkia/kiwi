# ADR 0042: primary-screen scrollback wheel policy

## Decision

Map vertical host-wheel input to local primary-screen history navigation only
when terminal mouse tracking is disabled. Retain a fractional delta remainder
per terminal session, emit integral row moves, and cap one host event at 16
rows. Reset that remainder when the direction changes or the terminal enters
an alternate screen or application mouse mode.

## Context

The terminal state already owns a bounded primary scrollback ring and exposes
`scroll_history`. Host wheel events previously reached only the terminal mouse
encoder; without application mouse tracking they had no primary-screen effect.
That makes ordinary shell history unusable with a wheel or touchpad.

## Consequences

The policy lives in `kiwi.input.scrollback_wheel`, before each host delegates a
wheel event to `kiwi.input.mouse`. It has no renderer, PTY, or native-widget
dependency, so GLFW, GTK WGPU, and the experimental GTK GL session route use
the same behavior. In a custom workspace, a wheel over an inactive pane first
activates that pane so the event cannot scroll a different session. An
application that has enabled mouse tracking retains all wheel reports; the
alternate screen retains its existing DECSET 1007 behavior.

The feature does not introduce a visible or native scrollbar. That remains a
separate presentation-level decision requiring pane geometry, hit testing,
accessibility, and macOS/GTK qualification.

## Evidence

`tests.test_scrollback_wheel` covers fractional accumulation, direction
changes, mode ownership, invalid deltas, and the per-event bound. The normal
test suite syntax-checks all three host routes.
