from __future__ import annotations

import os
import subprocess
import sys


def test_glasshouse_audio_plays_each_copied_event_once_under_dummy_sdl() -> None:
    source = """
import pygame

from kiwi.render.glasshouse_audio import GlasshouseSoundPlayer
from kiwi.ui.glasshouse_mission import GlasshouseSoundCue, GlasshouseSoundCueKind

pygame.init()
player = GlasshouseSoundPlayer()
cues = (
    GlasshouseSoundCue(1, GlasshouseSoundCueKind.FIRE),
    GlasshouseSoundCue(2, GlasshouseSoundCueKind.LOCKDOWN),
)
assert player.play(cues) == cues
assert player.play(cues) == ()
pygame.quit()
"""
    environment = dict(os.environ)
    environment["SDL_AUDIODRIVER"] = "dummy"
    environment["SDL_VIDEODRIVER"] = "dummy"

    result = subprocess.run(
        (sys.executable, "-c", source), check=False, capture_output=True, env=environment, text=True
    )

    assert result.returncode == 0, result.stderr
