from __future__ import annotations

import os
import subprocess
import sys


def test_development_picker_view_renders_selected_entries() -> None:
    source = """
import pygame
from pathlib import Path

from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.development_picker_view import (
    DEFAULT_DEVELOPMENT_PICKER_PALETTE,
    render_development_picker,
)
from kiwi.render.pygame_lifecycle import quit_pygame
from kiwi.ui.development_picker import DevelopmentPicker, PickerOption

font = load_bitmap_font()
canvas = pygame.Surface((240, 80))
canvas.fill((0, 0, 0))
policy = PickerOption(Path("policy.dtr"), "policies/policy.dtr")
fixture = PickerOption(Path("fixture.kfixture.json"), "fixtures/fixture.kfixture.json")
picker = DevelopmentPicker((policy,), (fixture,), policy.path, fixture.path)
result = render_development_picker(canvas, font, picker, (0, 0))
pixels = {canvas.get_at((x, y))[:3] for x in range(240) for y in range(80)}

assert result.line_count == 4
assert DEFAULT_DEVELOPMENT_PICKER_PALETTE.selected in pixels
assert DEFAULT_DEVELOPMENT_PICKER_PALETTE.heading in pixels
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
