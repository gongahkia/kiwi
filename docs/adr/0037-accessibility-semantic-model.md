# ADR 0037: accessibility semantic model

## Decision

Kiwi provides `kiwi.accessibility.model` as the sole terminal-core boundary for
future accessibility adapters. It produces detached, versioned v1 snapshots of
the active viewport's grapheme-safe terminal text, caret, selection, and range
metadata. `poll` compares consecutive bounded snapshots and reports at most one
event each for resize, viewport, output, caret, and selection in a fixed order.

The model uses stable terminal line IDs and cell-gap columns. It has no font,
pixel, screen-coordinate, platform, PTY, parser, renderer, shell-integration,
command-region, hyperlink-target, or native-handle dependency. An adapter owns
native accessibility objects and notification scheduling; terminal state owns
all text/history/selection semantics.

The default export is limited to 256 current-viewport rows and 65,536 UTF-8
bytes. When a grid is taller, the bounded slice is centered around the cursor
where possible and reports omitted rows. It never walks retained scrollback
except through the currently visible rows. A selection retains endpoints only,
not reconstructed private text. Continuation cells are omitted from row text;
wide/combining ranges snap to their complete semantic cluster.

## Consequences

This gives Linux AT-SPI, macOS NSAccessibility, and Windows UI Automation
adapters a common input without making any platform claim. It also avoids pixel
scraping and preserves the state model's scrollback/width authority. A native
adapter must create/destroy the model with its window and verify events with
actual platform tooling before Kiwi claims screen-reader support.

Focused tests cover Unicode, wide/combining range mapping, selection endpoints,
resize event ordering, history viewport updates, and a scrollback case that
proves the exporter does not materialize the retained document. The current
Linux checkout has no implemented adapter, so no AT-SPI or screen-reader result
is claimed. A future provider must expose the required Accessible/Application
D-Bus objects and complete the registry `Socket.Embed` handshake; availability
of the `atspi-2` client library alone is not adapter evidence.

## References

- [ACCESSIBILITY.md](../ACCESSIBILITY.md)
- [ADR 0021](0021-grapheme-aware-selection-state.md)
- [ADR 0023](0023-selection-render-pass.md)
- [TEXT.md](../TEXT.md)
- [AT-SPI provider documentation](https://gnome.pages.gitlab.gnome.org/at-spi2-core/devel-docs/)
