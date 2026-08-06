from __future__ import annotations

import os
import subprocess
import sys


def test_diagnostic_view_renders_inline_markers_and_panel_rows_with_bitmap_font() -> None:
    source = """
import pygame

from kiwi.dsl.diagnostics import Diagnostic, DiagnosticSeverity, DiagnosticStage
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.diagnostics_view import (
    DEFAULT_DIAGNOSTIC_PALETTE,
    render_diagnostic_panel,
    render_inline_diagnostics,
)
from kiwi.render.pygame_lifecycle import quit_pygame
from kiwi.ui.diagnostics import present_diagnostics

font = load_bitmap_font()
canvas = pygame.Surface((480, 96))
canvas.fill((0, 0, 0))
source = SourceFile(SourceFileId("policy.dtr"), "value\\nnext")
error = Diagnostic(
    "E200_EXAMPLE",
    DiagnosticSeverity.ERROR,
    "bad value",
    source.span(ByteOffset(1), ByteOffset(4)),
    DiagnosticStage.CHECKER,
)
warning = Diagnostic(
    "W100_EXAMPLE",
    DiagnosticSeverity.WARNING,
    "check next",
    source.span(ByteOffset(6), ByteOffset(10)),
    DiagnosticStage.CHECKER,
)
presentation = present_diagnostics(source, (warning, error))
inline = render_inline_diagnostics(canvas, font, source, presentation, (0, 0))
panel = render_diagnostic_panel(canvas, font, presentation, (0, 32))
pixels = {canvas.get_at((x, y))[:3] for x in range(480) for y in range(96)}

assert inline.entry_count == 2
assert panel.entry_count == 2
assert DEFAULT_DIAGNOSTIC_PALETTE.error in pixels
assert DEFAULT_DIAGNOSTIC_PALETTE.warning in pixels
quit_pygame()
"""
    environment = dict(os.environ)
    environment["SDL_AUDIODRIVER"] = "dummy"
    environment["SDL_VIDEODRIVER"] = "dummy"

    result = subprocess.run(
        (sys.executable, "-c", source),
        check=False,
        capture_output=True,
        env=environment,
        text=True,
    )

    assert result.returncode == 0, result.stderr
