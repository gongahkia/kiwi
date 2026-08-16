# ADR 0021: grapheme-aware selection state

## Decision

Store one bounded selection in terminal state as two directional endpoints, `anchor` and `focus`. An endpoint is a stable terminal-row ID plus a cell-gap column from `0` through `columns`; a selected range is the normalized half-open interval `[start, finish)`. The model stores no selected text, renderer data, byte offsets, or clipboard payload.

Rows receive monotonically increasing IDs when a screen creates them. Primary-screen selection order is oldest retained scrollback row followed by current primary rows; alternate-screen order is its current rows only. A primary row keeps its ID when normal scrolling moves it into scrollback. `history_offset` only changes the viewport and never rewrites selection endpoints.

When normalizing a range, a boundary that lands in a wide-cell continuation snaps outwards: the lower boundary moves to the anchor and the upper boundary moves after the complete cluster. Combining code points are already represented by their anchor cell, so a gap cannot split them. The directional endpoints remain available for gesture consumers, while `selection_view()` returns detached, normalized data for consumers; modifying that result cannot change terminal state.

On a primary-screen column resize, Kiwi reflows the bounded scrollback-plus-screen document and translates both endpoints through the same old-row/cell-gap to new-row/cell-gap map. The first output segment keeps each logical line's first row ID; later segments receive new IDs. A selection therefore follows text through ordinary reflow and is snapped again against the resulting wide cells. The primary scrollback limit remains a physical-row cap, so a narrowing resize can evict reflowed rows; if either remapped endpoint is no longer retained, the complete selection clears. Alternate-screen resize remains fixed-grid and clamps retained endpoints. A selection from the inactive screen remains stored but has `visible=false` until that screen is active.

## Rationale

Raw offsets cannot safely identify terminal text: a rendered cell may anchor multiple code points, and a wide glyph occupies an anchor plus continuation cell. Row IDs retain the semantic connection when terminal scrolling changes viewport coordinates, while keeping state to two endpoints regardless of scrollback size.

The model is deliberately independent of pointer events, rendering, and clipboard APIs. It gives each later layer the same normalized gap range, avoiding duplicate Unicode boundary decisions and avoiding retention of potentially large copied text in terminal state.

## Consequences

`State:set_selection(anchor_row, anchor_column, focus_row, focus_column)` maps clamped viewport coordinates to the active screen’s stable rows. `State:selection_view()` is the renderer/clipboard boundary. Pointer work must convert a cell hit to the documented gap before invoking it; copy work must reconstruct text only from the detached view and must follow ADR 0020’s size and security policy.

The selection is not yet drawn, copied, searched, persisted in replay, or exposed through an accessibility API. Terminal writes may change the content of a still-retained selected row; selection state preserves the range, not a historical text snapshot. Tests cover ASCII, reverse input, wide/combining clusters, history, eviction, resize, dropped rows, coordinate clamps, and alternate-screen visibility.
