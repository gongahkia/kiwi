from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def test_terminal_demo_renders_briefing_mission_debrief_and_comparison_states() -> None:
    source = """
import pygame

from kiwi.app.terminal_demo import TerminalDemoController
from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.terminal_demo import _fit_text, _render
from kiwi.render.terminal_workbench_view import DEFAULT_TERMINAL_WORKBENCH_PALETTE
from kiwi.render.pygame_lifecycle import quit_pygame

controller = TerminalDemoController.create()
font = load_bitmap_font()
assert font.measure(
    _fit_text(font, "initial state; next step evaluates the scout policy", 400)
)[0] <= 400
canvas = pygame.Surface((480, 270))
_render(canvas, font, controller)
assert len({canvas.get_at((x, y))[:3] for x in range(480) for y in range(270)}) > 2
controller = controller.confirm_input_mode().open_live_preview()
_render(canvas, font, controller)
_render(canvas, font, controller.cycle_color_scheme().open_results())
controller = controller.open_debrief()
_render(canvas, font, controller)
controller = controller.guide_revision().select_scout_threshold()
_render(canvas, font, controller)
pixels = {canvas.get_at((x, y))[:3] for x in range(480) for y in range(270)}
assert DEFAULT_TERMINAL_WORKBENCH_PALETTE.focus in pixels
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


def test_terminal_demo_keyboard_flow_runs_the_complete_manual_drill() -> None:
    source = """
import pygame

from kiwi.app.terminal_demo import (
    TerminalColorScheme,
    TerminalDemoController,
    TerminalDemoScreen,
)
from kiwi.render.terminal_demo import _handle_event
from kiwi.render.pygame_lifecycle import quit_pygame
from kiwi.ui.editor import EditorState

pygame.init()
controller = TerminalDemoController.create()
controller, quit_requested = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_1, mod=0, unicode="1")
)
assert not quit_requested
controller, quit_requested = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_RETURN, mod=0, unicode="\\r")
)
assert not quit_requested
assert controller.screen is TerminalDemoScreen.BRIEFING
controller, quit_requested = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_RETURN, mod=0, unicode=\"\\r\")
)
assert not quit_requested
assert controller.screen is TerminalDemoScreen.LIVE_PREVIEW
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_F1, mod=0, unicode=\"\")
)
assert controller.screen is TerminalDemoScreen.GUIDE
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_ESCAPE, mod=0, unicode=\"\")
)
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_F5, mod=0, unicode=\"\")
)
assert controller.screen is TerminalDemoScreen.LOADING
controller = controller.finish_deploy()
assert controller.screen is TerminalDemoScreen.LIVE_PREVIEW
controller, _ = _handle_event(
    controller,
    pygame.event.Event(
        pygame.KEYDOWN, key=pygame.K_EQUALS, mod=pygame.KMOD_SHIFT, unicode="+"
    ),
)
assert controller.preview_zoom_percent == 125
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_RETURN, mod=0, unicode=\"\\r\")
)
assert controller.screen is TerminalDemoScreen.DEBRIEF
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
assert controller.screen is TerminalDemoScreen.LOADING
controller = controller.finish_deploy()
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_RETURN, mod=0, unicode=\"\\r\")
)
assert controller.screen is TerminalDemoScreen.COMPARISON
controller = controller.return_to_live_preview().replace_selected_editor(
    EditorState.from_text(\"Mov\").move_cursor(3)
)
controller, _ = _handle_event(
    controller, pygame.event.Event(pygame.KEYDOWN, key=pygame.K_TAB, mod=0, unicode=\"\\t\")
)
assert controller.workbench.source.text == \"MoveToward\"
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


def test_terminal_demo_clicks_position_the_editor_and_activate_compile_buttons() -> None:
    source = """
import pygame

from kiwi.app.terminal_demo import (
    TerminalColorScheme,
    TerminalDemoController,
    TerminalDemoScreen,
)
from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.terminal_demo import (
    _handle_click,
    _live_preview_panes,
    _preview_buttons,
    _theme_button,
    _workbench_buttons,
)
from kiwi.render.pygame_lifecycle import quit_pygame

pygame.init()
font = load_bitmap_font()
controller = TerminalDemoController.create(platform_name="Darwin")
controller = _handle_click(controller, (25, 160), font)
assert controller.screen is TerminalDemoScreen.BRIEFING
controller = controller.open_live_preview()
selected_line = controller.workbench.editor.scroll.line
controller = _handle_click(controller, (260, 32), font)
assert controller.workbench.editor.cursor_position.line == selected_line
left_rect, right_rect = _live_preview_panes(pygame.Surface((960, 540)))
theme_button = _theme_button(pygame.Surface(left_rect.size), font)
controller = _handle_click(controller, theme_button.center, font)
assert controller.color_scheme is TerminalColorScheme.AMBER
compile_button, deploy_button = _workbench_buttons(pygame.Surface(left_rect.size), font)
controller = _handle_click(controller, compile_button.center, font)
assert controller.workbench.compile_output is not None
assert controller.workbench.compile_output.succeeded
controller = _handle_click(controller, deploy_button.center, font)
assert controller.screen is TerminalDemoScreen.LOADING
controller = controller.finish_deploy()
assert controller.screen is TerminalDemoScreen.LIVE_PREVIEW
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


def test_retained_impact_feedback_decays_without_an_authority_input() -> None:
    from kiwi.render.terminal_demo import _impact_feedback

    assert _impact_feedback(0) == ((-4, 4), 4)
    assert _impact_feedback(315) == ((1, 1), 1)
    assert _impact_feedback(360) == ((0, 0), 0)


def test_terminal_demo_only_notices_when_local_settings_need_attention(tmp_path: Path) -> None:
    from kiwi.app.settings import load_ui_settings
    from kiwi.app.terminal_codex import load_terminal_codex_result
    from kiwi.render.terminal_demo import _persistence_notice

    settings_path = tmp_path / "settings.json"
    empty_notice = _persistence_notice(
        load_ui_settings(settings_path),
        load_terminal_codex_result(tmp_path / "codex.json"),
        settings_path,
    )
    settings_path.write_text("{", encoding="utf-8")
    corrupt_notice = _persistence_notice(
        load_ui_settings(settings_path),
        load_terminal_codex_result(tmp_path / "codex.json"),
        settings_path,
    )

    assert empty_notice == ""
    assert corrupt_notice == "Settings could not be loaded; using defaults."
