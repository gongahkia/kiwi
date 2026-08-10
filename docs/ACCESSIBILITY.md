# Accessibility semantic model

`kiwi.accessibility.model` is a platform-neutral data layer for future Linux,
macOS, and Windows accessibility adapters. It is not an AT-SPI, NSAccessibility,
or UI Automation adapter, and Kiwi does not claim screen-reader support until
one of those adapters is implemented and validated in its native environment.

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

## Adapter procedure

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

An adapter must test the active terminal window with its native inspection and
screen-reader tooling before advertising support. It must preserve the bounds,
keep inaccessible shell/region data private by default, and document any
platform-specific selection or caret mapping. The semantic model's unit tests
cover Unicode anchors, wide cells, combining text, selection, resize, history
viewports, and bounded scrollback export; they are not a screen-reader smoke
test.
