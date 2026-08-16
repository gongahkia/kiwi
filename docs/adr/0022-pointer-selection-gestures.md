# ADR 0022: pointer selection gestures

## Decision

When application mouse tracking is inactive, Kiwi uses primary-button pointer events for one local selection. GLFW gives pointer locations in logical window units. Input maps them to a zero-based viewport cell with `floor(position * content_scale / cell_size)` and clamps the result to the current `0..columns - 1` and `0..rows - 1` ranges before passing it to terminal state. The current font, content scale, and state dimensions are read for every callback, so a resize or history viewport change has no cached coordinate map.

A primary press places an empty selection at the hit grapheme cell's leading gap. Dragging includes the hit cell in the direction of travel, with wide-cell continuations expanded to their complete cluster; release applies the same range unless it is still on the initial cluster. Therefore a click without a drag leaves an empty selection. Selection state maps the viewport row to its stable row ID, so a history viewport selects the retained scrollback row rather than a primary-screen row at the same coordinate.

Clicks at the same logical position within 0.4 seconds and within four logical units count as a sequence. The second click selects one word and the third selects the full physical grid row (`[0, columns)`). A fourth click begins a new sequence. A word is a contiguous run of grapheme anchors whose first code point is ASCII `A-Z`, `a-z`, `0-9`, `_`, or at least U+0080. Punctuation, whitespace, and an empty cell each select only their own grapheme cell. This is deliberately a stable terminal policy, not locale-sensitive word breaking.

Enabled X10 (`?9`), normal (`?1000`), button-event (`?1002`), or any-event (`?1003`) tracking takes precedence over local selection. Those events are forwarded to the child through the active classic, UTF-8, URXVT, or SGR mouse encoder, and any local drag is cancelled. M4 provides no Shift or other modifier override. Other buttons and wheel events do not create local selections.

## Rationale

The selection model is already grapheme-safe and stable across bounded primary scrollback. Keeping conversion and gestures in a small input boundary reuses that model rather than retaining display text or duplicating row-history logic in GLFW callbacks. The application mouse precedence matches full-screen TUI expectations without guessing which modifiers a program will use.

## Consequences

The gesture updates terminal selection state. The later renderer draws that
state, the clipboard layer reconstructs a bounded copy, and the Linux AT-SPI
provider projects its endpoints as read-only character offsets. It has no
hyperlink action, IME integration, or replay event format. Clipboard behavior
remains governed by ADR 0020. Tests cover scaled/clamped coordinates, forward
and reverse wide-cell drags, double/triple expansion, scrollback/resize
behavior, and application-mouse precedence.
