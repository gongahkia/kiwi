from __future__ import annotations

import os
import subprocess
import sys


def test_terminal_audio_plays_each_copied_event_once_under_dummy_sdl() -> None:
    source = """
import pygame

from kiwi.render.terminal_audio import TerminalSoundPlayer
from kiwi.ui.terminal_mission import TerminalSoundCue, TerminalSoundCueKind

pygame.init()
player = TerminalSoundPlayer()
cues = (
    TerminalSoundCue(1, TerminalSoundCueKind.FIRE),
    TerminalSoundCue(2, TerminalSoundCueKind.LOCKDOWN),
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
