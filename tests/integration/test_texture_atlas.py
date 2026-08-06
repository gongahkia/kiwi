from __future__ import annotations

import os
import subprocess
import sys


def test_glasshouse_atlas_preserves_transparent_backgrounds_when_tinted() -> None:
    source = """
import pygame

from kiwi.render.atlas import load_glasshouse_atlas
from kiwi.render.pygame_lifecycle import quit_pygame

pygame.init()
pygame.display.set_mode((1, 1))
atlas = load_glasshouse_atlas()
assert atlas is not None
operative = atlas.frame("operative", 48, (255, 255, 255))
assert operative.get_at((0, 0)).a == 0
assert any(operative.get_at((x, y)).a == 255 for x in range(48) for y in range(48))
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
