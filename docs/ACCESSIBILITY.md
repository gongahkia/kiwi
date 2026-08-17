# Accessibility semantic model

`kiwi.accessibility.model` is the platform-neutral terminal-semantic layer for
accessibility adapters. Linux has a native AT-SPI provider and macOS has a
native NSAccessibility element built on top of that model. Windows UI
Automation is unimplemented, and Kiwi does not yet make an end-to-end
screen-reader compatibility claim.

## Contract

```lua
local Accessibility = require("kiwi.accessibility.model")
local model = Accessibility.new({ max_rows = 256, max_bytes = 65536 })
local snapshot, events = model:poll(terminal_state)
```

`snapshot.version` is `1`. It contains detached plain-data descriptors:

| Field | Content | Boundaries |
| --- | --- | --- |
| `viewport` | active scope, history offset, grid dimensions, exported slice, omitted row count, first/last stable line IDs | at most `max_rows` visible physical rows; no scrollback traversal/materialization |
| `text.rows` | stable line ID, viewport row, full cell-gap range, glyph text, soft-wrap flag, truncation flag | at most `max_bytes` of anchor glyph text; continuation cells are skipped |
| `caret` | scope, stable line ID, cell-gap column, viewport row, visibility | one current cursor only |
| `selection` | active/empty/visible flags, scope, stable start/finish line-ID cell gaps | no reconstructed selection text |

`model:range_at(state, row, column)` converts a visible cell to one
grapheme-safe range. A wide-cell continuation snaps to its anchor and returns
the complete two-cell range; combining code points remain in their anchor
glyph. This keeps the adapter contract aligned with terminal width rather than
with font advances or rendered pixels.

`model:poll(state)` returns the current snapshot and no more than five events,
in this deterministic order: `resize`, `viewport`, `output`, `caret`, then
`selection`. The first call returns one `initial` event. Events contain only
the changed detached descriptor; output contains no text payload because an
adapter reads the bounded snapshot itself. A platform bridge decides how to map
these events to native accessibility notifications and retains no terminal
ownership.

The model never exports parser input, PTY bytes, command-region data, shell
metadata, OSC payloads, hyperlink targets, font/WGPU handles, renderer data,
or unbounded scrollback. It has no native allocation or cleanup responsibility.
Its only retained state is the previous bounded snapshot used for change
comparison.

## Semantic-model procedure

1. Create one model per terminal window and publish its initial snapshot after
   the native accessibility object exists.
2. Poll after terminal output/input processing and after resize, selection, or
   history viewport changes. Translate its events on the platform's required
   UI thread.
3. On accessibility text/range queries, read a fresh snapshot or
   `range_at`; do not reconstruct ranges from glyph pixels or cache text past
   the next poll.
4. Destroy the model with the native window/accessibility object. There are no
   native handles to release.

An adapter must preserve the bounds, keep shell/region data private by default,
and document its platform-specific selection and caret mapping. The semantic
model's unit tests cover Unicode anchors, wide cells, combining text,
selection, resize, history viewports, and bounded scrollback export; they are
not a screen-reader test.

## Native Linux boundary

`native/accessibility.c` is a GIO/D-Bus server compiled into the existing
native bridge. On startup, unless `KIWI_ACCESSIBILITY=0`, it obtains the
dedicated accessibility-bus address from `org.a11y.Bus`, exports an application
root at `/org/a11y/atspi/accessible/root`, exports a terminal child at
`/org/a11y/atspi/accessible/terminal`, and registers the root with the
registry's `org.a11y.atspi.Socket.Embed` handshake. It does not attempt to use
the ordinary session bus as the registry.

The root implements `Accessible` and `Application`; the child implements
`Accessible` and `Text`. The child represents the active Kiwi pane, reports
terminal and focusable states, uses the current safe window title as its
accessible name, and exports a fresh bounded projection after each live-event
turn. The projection contains at most 256 physical viewport rows and 64 KiB of
UTF-8 text. It inserts LF separators between physical rows, collapses wide-cell
continuation cells, and maps caret/selection cell gaps to UTF-8 character
offsets. It does not traverse or materialize retained scrollback outside that
bounded viewport.

The provider supports text fetches, character reads, character and physical
line ranges, caret, and the current local selection. It emits bounded whole-
viewport replacement events for output, caret movement, selection changes, and
focus-state changes. `SetCaretOffset` and selection mutation methods remain
read-only because terminal output is not an editable text buffer. Precise word
and sentence segmentation, styled text attributes, geometry/component APIs,
multiple simultaneously exposed panes, and native window notifications are not
implemented. Non-character `GetStringAtOffset` granularities deliberately
return the physical line rather than claiming locale-aware word or sentence
segmentation.

The provider is optional: inability to contact the session or accessibility bus
does not stop Kiwi. Set `KIWI_ACCESSIBILITY_DIAGNOSTICS=1` to report that
fallback. The installed `atspi-2` client library is not used for provider
registration; GIO owns the exported objects and their lifecycle.

## Native macOS boundary

`native/accessibility_macos.m` acquires GLFW's Cocoa content view on the main
thread and attaches one bounded read-only `NSAccessibilityTextArea` element for
the active Kiwi pane. The element uses the safe terminal title as its label and
the current bounded viewport text as its value. It maps the platform-neutral
Unicode-scalar caret/selection offsets into NSString's UTF-16 offset space,
exposes visible, selected, and insertion ranges, and emits value, selected-text,
and focus notifications after updates. It is removed again when Kiwi destroys
the window. The adapter does not expose editable terminal text, styled
attributes, geometry for individual terminal cells, or multiple panes as
separate accessibility elements.

`make cocoa-smoke` creates this adapter and checks its text-area role,
identifier, label, UTF-8 value, visible/selected ranges, focus state, and
teardown restoration on a real Cocoa view. `make voiceover-validation` runs
that adapter contract explicitly. `make accessibility-smoke` runs the
deterministic semantic checks and reports this macOS boundary.
`make accessibility-provider-smoke` is intentionally an AT-SPI-only test and
reports a skip on macOS. No automated check can establish spoken output or
real VoiceOver navigation, so focus, selection, resize, and pane-change
usability still need a manual VoiceOver session.

## M9 smoke evidence

`make accessibility-smoke` runs the deterministic semantic tests, builds the
native bridge, and reports the AT-SPI library, local registry executable,
assistive-tool availability, and registry reachability. It is safe in a
non-graphical session and does not open a window.

`make accessibility-provider-smoke` is the live Linux protocol test. It opens
a short-lived Kiwi window, waits for its registry registration, and verifies
from a separate D-Bus client that the registry exposes a Kiwi root and terminal
child whose accessible name contains the child-process OSC 2 title and whose
bounded text contains the child-process sentinel. It verifies that
`Text.CharacterCount` is positive and observes a subsequent `TextChanged`
event. It skips only when the desktop display, `gdbus`, `org.a11y.Bus`, or the
registry is unavailable.

On the assessed Fedora 43 desktop, the provider handshake and external text
query passed using AT-SPI 2.58.7. This is protocol-level evidence, not an Orca
or other screen-reader interaction test. A manual assistive-technology session
must still check spoken output changes, navigation behavior, focus transitions,
and selection reporting before Kiwi can claim screen-reader compatibility.
macOS needs a manual VoiceOver result; Windows still needs its native adapter.

## References

- [AT-SPI Accessible provider contract](https://gnome.pages.gitlab.gnome.org/at-spi2-core/devel-docs/doc-org.a11y.atspi.Accessible.html)
- [AT-SPI Application provider contract](https://gnome.pages.gitlab.gnome.org/at-spi2-core/devel-docs/doc-org.a11y.atspi.Application.html)
- [AT-SPI registry `Socket.Embed` handshake](https://gnome.pages.gitlab.gnome.org/at-spi2-core/devel-docs/doc-org.a11y.atspi.Socket.html)
- [AT-SPI Text interface](https://gnome.pages.gitlab.gnome.org/at-spi2-core/devel-docs/doc-org.a11y.atspi.Text.html)
