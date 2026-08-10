# ADR 0030: command-region navigation

## Context

Bounded region records and row associations make it possible to move through a
cooperating shell transcript, but ordinary terminal keys must continue to reach
programs unless a deliberate local binding owns them. Navigation also cannot
pretend that an evicted or incomplete region still has a visible destination.

## Decision

Kiwi reserves these local bindings before Kitty keyboard encoding:

| Binding | Action |
| --- | --- |
| `Ctrl+Alt+P` / `Ctrl+Shift+Alt+P` | previous / next prompt boundary |
| `Ctrl+Alt+C` / `Ctrl+Shift+Alt+C` | previous / next command boundary |
| `Ctrl+Alt+O` / `Ctrl+Shift+Alt+O` | previous / next output boundary |

The bindings never enqueue PTY bytes. They are explicitly gated: alternate
screen returns `alternate-screen`, negotiated Kitty keyboard mode returns
`keyboard-mode`, and an active search query returns `search-active`. The app
consumes the reserved chord and reports a local status without changing the
viewport when gated. This avoids inventing a command palette or sending a
half-local navigation key to a child application.

For the active primary screen, Kiwi resolves the requested role position
against currently retained primary rows, sorts candidates by document row,
column, then region ID, and moves only `history_offset`. Repeated navigation of
the same role advances from the last chosen region. A first navigation is
relative to the live cursor, or the top visible history row when history is
already open. There is no wrapping: exhausted directions return `start` or
`end`; no retained requested role returns `no-region`.

Coverage is advisory rather than a guessed destination. A `partial` or
`truncated` region remains eligible only when its exact requested role position
resolves to a retained primary row. `evicted`, missing, alternate-screen, and
incomplete-role positions are absent from the candidate list. An output may be
navigable after its prompt is evicted, while a prompt request returns
`no-region`.

Navigation does not change terminal cells, selection endpoints, clipboard,
shell metadata, command lifecycle, or replay bytes. A local selection remains
intact while the viewport moves. Editing search owns its input and gates
navigation; an already-submitted search result remains unchanged. Manual
history scrolling clears the local navigation cursor so the next action is
again relative to the viewport.

## Consequences

The minimal state surface is a detached target list and one local
`{role, region_id}` navigation cursor. No renderer resource or accessibility
export is introduced; later consumers can use the same resolved
position/status boundary rather than infer command text or row ownership.
Tests cover binding reservation, ordering, start/end/no-region behavior,
partial/evicted targets, selection/search, alternate screen, and keyboard mode
gating.

The native long-shell child validates record/replay retention, but cannot
exercise physical key chords without driving the focused graphical surface.
Manual compositor verification remains distinct and must not send shortcuts to
an unrelated focused application.

## References

- [ADR 0028](0028-stable-command-region-lifecycle.md)
- [ADR 0029](0029-command-region-retention-and-snapshot-boundary.md)
