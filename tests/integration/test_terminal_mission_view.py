from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def test_terminal_mission_view_renders_authority_snapshot_and_signal_status() -> None:
    source = """
from pathlib import Path

import pygame

from kiwi.app.terminal_execution import (
    TerminalMissionExecution,
    TerminalSignal,
    build_terminal_mission_execution,
    build_terminal_mission_presentation,
)
from kiwi.app.terminal_hostiles import TERMINAL_HOSTILE_LOADOUTS
from kiwi.app.terminal_players import TERMINAL_PLAYER_LOADOUTS
from kiwi.app.terminal_workbench import build_terminal_workbench
from kiwi.content.missions import load_mission_file
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.camera import Camera
from kiwi.render.terminal_mission_view import (
    DEFAULT_TERMINAL_MISSION_PALETTE,
    render_terminal_mission,
)
from kiwi.render.pygame_lifecycle import quit_pygame

root = Path.cwd()
sources = lambda loadouts: tuple(
    SourceFile(
        SourceFileId(loadout.policy_file_id),
        (root / loadout.policy_file_id).read_text(encoding=\"utf-8\"),
    )
    for loadout in loadouts
)
workbench = build_terminal_workbench(sources(TERMINAL_PLAYER_LOADOUTS)).open_workbench()
execution = build_terminal_mission_execution(
    load_mission_file(root / \"examples/missions/terminal.dmission.json\"),
    workbench,
    sources(TERMINAL_HOSTILE_LOADOUTS),
)
assert isinstance(execution, TerminalMissionExecution)
execution = execution.request_start().advance().queue_signal(TerminalSignal.HOLD)
font = load_bitmap_font()
canvas = pygame.Surface((480, 270))
result = render_terminal_mission(
    canvas,
    font,
    build_terminal_mission_presentation(execution),
    Camera(pixels_per_millimetre=0.01),
)
pixels = {canvas.get_at((x, y))[:3] for x in range(480) for y in range(270)}
assert result.line_count == 5
assert DEFAULT_TERMINAL_MISSION_PALETTE.heading in pixels
assert DEFAULT_TERMINAL_MISSION_PALETTE.signal in pixels
assert DEFAULT_TERMINAL_MISSION_PALETTE.border in pixels
quit_pygame()
"""
    environment = dict(os.environ)
    environment["SDL_AUDIODRIVER"] = "dummy"
    environment["SDL_VIDEODRIVER"] = "dummy"

    result = subprocess.run(
        (sys.executable, "-c", source),
        check=False,
        capture_output=True,
        cwd=Path(__file__).resolve().parents[2],
        env=environment,
        text=True,
    )

    assert result.returncode == 0, result.stderr
