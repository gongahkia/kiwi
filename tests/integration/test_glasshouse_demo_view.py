from __future__ import annotations

import os
import subprocess
import sys


def test_glasshouse_demo_renders_briefing_mission_debrief_and_comparison_states() -> None:
    source = """
import pygame

from kiwi.app.glasshouse_demo import GlasshouseDemoController
from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.glasshouse_demo import _fit_text, _render
from kiwi.render.glasshouse_workbench_view import DEFAULT_GLASSHOUSE_WORKBENCH_PALETTE
from kiwi.render.pygame_lifecycle import quit_pygame

controller = GlasshouseDemoController.create()
font = load_bitmap_font()
assert font.measure(
    _fit_text(font, "initial state; next step evaluates the scout policy", 400)
)[0] <= 400
canvas = pygame.Surface((480, 270))
_render(canvas, font, controller)
assert len({canvas.get_at((x, y))[:3] for x in range(480) for y in range(270)}) > 2
controller = controller.confirm_input_mode().open_workbench().deploy()
_render(canvas, font, controller)
controller = controller.open_debrief()
_render(canvas, font, controller)
controller = controller.guide_revision().select_scout_threshold()
_render(canvas, font, controller)
pixels = {canvas.get_at((x, y))[:3] for x in range(480) for y in range(270)}
assert DEFAULT_GLASSHOUSE_WORKBENCH_PALETTE.focus in pixels
editor = controller.workbench.editor.insert_text(\"0\")
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
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_1, mod=0, unicode="1")
)
assert not quit_requested
controller, quit_requested = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_RETURN, mod=0, unicode="\\r")
)
assert not quit_requested
assert controller.screen is GlasshouseDemoScreen.BRIEFING
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
assert controller.screen is GlasshouseDemoScreen.LIVE_PREVIEW
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
for key, text in ((pygame.K_0, \"0\"),):
    controller, _ = _handle_event(
        controller, pygame.event.Event(pygame.KEYDOWN, key=key, mod=0, unicode=text)
    )
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_F5, mod=0, unicode=\"\")
)
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_RETURN, mod=0, unicode=\"\\r\")
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


def test_glasshouse_demo_clicks_position_the_editor_and_activate_compile_buttons() -> None:
    source = """
import pygame

from kiwi.app.glasshouse_demo import GlasshouseDemoController, GlasshouseDemoScreen
from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.glasshouse_demo import (
    _handle_click,
    _live_preview_panes,
    _preview_buttons,
    _workbench_buttons,
)
from kiwi.render.pygame_lifecycle import quit_pygame

pygame.init()
font = load_bitmap_font()
controller = GlasshouseDemoController.create(platform_name="Darwin")
controller = _handle_click(controller, (25, 160), font)
assert controller.screen is GlasshouseDemoScreen.BRIEFING
controller = controller.open_workbench()
controller = _handle_click(controller, (260, 32), font)
assert controller.workbench.editor.cursor_position.line == 1
compile_button, deploy_button = _workbench_buttons(pygame.Surface((960, 540)), font)
controller = _handle_click(controller, compile_button.center, font)
assert controller.workbench.compile_output is not None
assert controller.workbench.compile_output.succeeded
controller = _handle_click(controller, deploy_button.center, font)
assert controller.screen is GlasshouseDemoScreen.LIVE_PREVIEW
left_rect, right_rect = _live_preview_panes(pygame.Surface((960, 540)))
play_button, step_button, reload_button, _ = _preview_buttons(pygame.Surface(right_rect.size), font)
controller = _handle_click(
    controller, (right_rect.x + play_button.centerx, play_button.centery), font
)
assert not controller.preview_playing
controller = _handle_click(
    controller, (right_rect.x + step_button.centerx, step_button.centery), font
)
assert controller.preview_snapshot_index == 1
controller = _handle_click(
    controller, (right_rect.x + reload_button.centerx, reload_button.centery), font
)
assert not controller.hot_reload_enabled
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
