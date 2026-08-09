import os
import sys


if os.name == "nt":
    os.add_dll_directory(os.environ["STROK_LIBRARY_DIR"])

import strok


if strok.abi_version() != 0x00010003:
    raise SystemExit(f"unexpected strok C ABI version: {strok.abi_version():#x}")

if strok.__all__ != ["CellBuffer", "Renderer", "StaleResultError", "abi_version"]:
    raise SystemExit("unexpected Python binding exports")


def expect(exception_type, callback):
    try:
        callback()
    except exception_type:
        return
    raise SystemExit(f"expected {exception_type.__name__}")


first_frame = bytes((0, 0, 0, 255, 0, 0, 0, 255, 0, 255, 255, 255))
second_frame = bytes((255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255))

renderer = strok.Renderer(2, 2)
expect(ValueError, renderer.cells)
expect(ValueError, lambda: renderer.render_rgb(b"\0", 1, 1))
renderer.render_rgb(first_frame, 2, 2)
cells = renderer.cells()
columns, rows = cells.dimensions()
if columns <= 0 or rows <= 0:
    raise SystemExit("renderer returned empty CellBuffer dimensions")
glyph, foreground, background = cells.cell(0, 0)
if not isinstance(glyph, str) or len(glyph) != 1 or len(foreground) != 3 or len(background) != 3:
    raise SystemExit("CellBuffer cell shape is invalid")
expect(IndexError, lambda: cells.cell(columns, 0))
renderer.reset()
cells.dimensions()

renderer.render_rgb(second_frame, 2, 2)
expect(strok.StaleResultError, cells.dimensions)


def retained_cells_after_renderer_name_is_dropped():
    retained_renderer = strok.Renderer(2, 2)
    retained_renderer.render_rgb(first_frame, 2, 2)
    return retained_renderer.cells()


retained_cells = retained_cells_after_renderer_name_is_dropped()
retained_cells.dimensions()
renderer.close()
expect(RuntimeError, renderer.cells)

sys.exit(0)
