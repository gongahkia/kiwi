from __future__ import annotations

import os
import subprocess
import sys


def test_glasshouse_demo_renders_briefing_mission_debrief_and_comparison_states() -> None:
    source = """
import pygame

from kiwi.app.glasshouse_demo import GlasshouseDemoController
from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.glasshouse_demo import _render
from kiwi.render.glasshouse_workbench_view import DEFAULT_GLASSHOUSE_WORKBENCH_PALETTE
from kiwi.render.pygame_lifecycle import quit_pygame

controller = GlasshouseDemoController.create()
font = load_bitmap_font()
canvas = pygame.Surface((480, 270))
_render(canvas, font, controller)
assert len({canvas.get_at((x, y))[:3] for x in range(480) for y in range(270)}) > 2
controller = controller.open_workbench().deploy()
_render(canvas, font, controller)
controller = controller.open_debrief()
_render(canvas, font, controller)
controller = controller.guide_revision().select_scout_threshold()
_render(canvas, font, controller)
pixels = {canvas.get_at((x, y))[:3] for x in range(480) for y in range(270)}
assert DEFAULT_GLASSHOUSE_WORKBENCH_PALETTE.focus in pixels
editor = controller.workbench.editor.insert_text(\"0m\")
controller = controller.replace_selected_editor(editor).deploy()
_render(canvas, font, controller.open_debrief())
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


def test_glasshouse_demo_keyboard_flow_runs_the_complete_manual_drill() -> None:
    source = """
import pygame

from kiwi.app.glasshouse_demo import GlasshouseDemoController, GlasshouseDemoScreen
from kiwi.render.glasshouse_demo import _handle_event
from kiwi.render.pygame_lifecycle import quit_pygame

pygame.init()
controller = GlasshouseDemoController.create()
controller, quit_requested = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_RETURN, mod=0, unicode=\"\\r\")
)
assert not quit_requested
assert controller.screen is GlasshouseDemoScreen.WORKBENCH
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_F1, mod=0, unicode=\"\")
)
assert controller.screen is GlasshouseDemoScreen.GUIDE
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_ESCAPE, mod=0, unicode=\"\")
)
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_F5, mod=0, unicode=\"\")
)
assert controller.screen is GlasshouseDemoScreen.MISSION
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_RETURN, mod=0, unicode=\"\\r\")
)
assert controller.screen is GlasshouseDemoScreen.DEBRIEF
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_r, mod=0, unicode=\"r\")
)
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_F2, mod=0, unicode=\"\")
)
for key, text in ((pygame.K_0, \"0\"), (pygame.K_m, \"m\")):
    controller, _ = _handle_event(
        controller, pygame.event.Event(pygame.KEYDOWN, key=key, mod=0, unicode=text)
    )
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_F5, mod=0, unicode=\"\")
)
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_c, mod=0, unicode=\"c\")
)
assert controller.screen is GlasshouseDemoScreen.COMPARISON
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
