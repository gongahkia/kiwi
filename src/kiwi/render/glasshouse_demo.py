"""pygame-ce shell for the runnable Glasshouse causal-drill usability flow."""

from __future__ import annotations

import pygame

from kiwi.app.glasshouse_demo import GlasshouseDemoController, GlasshouseDemoScreen
from kiwi.render.bitmap_font import BitmapFont, load_bitmap_font
from kiwi.render.camera import Camera
from kiwi.render.glasshouse_debrief_view import render_glasshouse_debrief
from kiwi.render.glasshouse_tutorial_view import render_glasshouse_tutorial
from kiwi.render.glasshouse_workbench_view import render_glasshouse_workbench
from kiwi.render.pygame_app import open_pygame_window, present, render_tactical_view
from kiwi.render.pygame_lifecycle import quit_pygame
from kiwi.render.run_comparison_view import render_run_comparison_view
from kiwi.sim.snapshot import build_presentation_snapshot
from kiwi.ui.editor import EditorState, TextPosition
from kiwi.ui.glasshouse_debrief import GlasshouseDebrief

_BACKGROUND = (10, 14, 19)
_PANEL = (20, 29, 36)
_BORDER = (68, 119, 142)
_HEADING = (111, 216, 238)
_NORMAL = (206, 221, 231)
_NOTICE = (245, 189, 74)
_MUTED = (192, 201, 191)
_FOOTER_HEIGHT = 16
_MAX_NOTICE_CHARACTERS = 58


def run_glasshouse_demo() -> int:
    """Run the local-only Glasshouse usability drill until its window closes."""
    window = open_pygame_window()
    pygame.display.set_caption("Kiwi — Glasshouse causal drill")
    font = load_bitmap_font()
    controller = GlasshouseDemoController.create()
    frame_clock = pygame.time.Clock()
    try:
        running = True
        while running:
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                    continue
                controller, should_quit = _handle_event(controller, event)
                running = running and not should_quit
            _render(window.logical_canvas, font, controller)
            present(window)
            frame_clock.tick(60)
    finally:
        quit_pygame()
    return 0


def _handle_event(
    controller: GlasshouseDemoController, event: pygame.event.Event
) -> tuple[GlasshouseDemoController, bool]:
    if event.type != pygame.KEYDOWN:
        return (controller, False)
    if event.key == pygame.K_ESCAPE:
        if controller.screen is GlasshouseDemoScreen.BRIEFING:
            return (controller, True)
        return (_escape(controller), False)
    if controller.screen is GlasshouseDemoScreen.BRIEFING:
        if event.key in (pygame.K_RETURN, pygame.K_SPACE):
            return (controller.open_workbench(), False)
        return (controller, False)
    if controller.screen is GlasshouseDemoScreen.GUIDE:
        if event.key in (pygame.K_RIGHT, pygame.K_DOWN, pygame.K_SPACE):
            return (controller.next_lesson(), False)
        if event.key in (pygame.K_LEFT, pygame.K_UP):
            return (controller.previous_lesson(), False)
        return (controller, False)
    if controller.screen is GlasshouseDemoScreen.WORKBENCH:
        return (_handle_workbench_key(controller, event), False)
    if controller.screen is GlasshouseDemoScreen.MISSION:
        if event.key in (pygame.K_RETURN, pygame.K_d):
            return (controller.open_debrief(), False)
        if event.key == pygame.K_c:
            return (controller.open_comparison(), False)
        if event.key == pygame.K_F5:
            return (controller.return_to_workbench().deploy(), False)
        return (controller, False)
    if controller.screen is GlasshouseDemoScreen.DEBRIEF:
        if event.key == pygame.K_r:
            return (controller.guide_revision(), False)
        return (controller, False)
    if controller.screen is GlasshouseDemoScreen.COMPARISON and event.key == pygame.K_F5:
        return (controller.return_to_workbench().deploy(), False)
    return (controller, False)


def _escape(controller: GlasshouseDemoController) -> GlasshouseDemoController:
    if controller.screen is GlasshouseDemoScreen.BRIEFING:
        return controller
    if controller.screen is GlasshouseDemoScreen.GUIDE:
        return controller.close_guide()
    return controller.return_to_workbench()


def _handle_workbench_key(
    controller: GlasshouseDemoController, event: pygame.event.Event
) -> GlasshouseDemoController:
    modifiers = event.mod
    command = modifiers & (pygame.KMOD_CTRL | pygame.KMOD_META)
    if event.key == pygame.K_F1:
        return controller.open_guide()
    if event.key == pygame.K_F2:
        return controller.select_scout_threshold()
    if event.key == pygame.K_F5:
        return controller.deploy()
    if event.key == pygame.K_TAB:
        direction = -1 if modifiers & pygame.KMOD_SHIFT else 1
        index = (controller.workbench.selected_policy_index + direction) % len(
            controller.workbench.policies
        )
        return controller.select_policy_index(index)
    if command and event.key in (pygame.K_RETURN, pygame.K_KP_ENTER):
        return controller.compile_selected()
    editor = controller.workbench.editor
    if command and event.key == pygame.K_z:
        return controller.replace_selected_editor(editor.undo())
    if command and event.key == pygame.K_y:
        return controller.replace_selected_editor(editor.redo())
    if event.key == pygame.K_BACKSPACE:
        return controller.replace_selected_editor(editor.delete_backward())
    if event.key == pygame.K_DELETE:
        return controller.replace_selected_editor(editor.delete_forward())
    if event.key in (pygame.K_RETURN, pygame.K_KP_ENTER):
        return controller.replace_selected_editor(editor.insert_newline())
    if event.key in (pygame.K_LEFT, pygame.K_RIGHT, pygame.K_UP, pygame.K_DOWN):
        return controller.replace_selected_editor(_move_editor(editor, event.key, modifiers))
    if event.key == pygame.K_HOME:
        return controller.replace_selected_editor(
            editor.move_to(TextPosition(editor.cursor_position.line, 1))
        )
    if event.key == pygame.K_END:
        line = editor.cursor_position.line
        return controller.replace_selected_editor(
            editor.move_to(TextPosition(line, editor.buffer.line_index.max_column(line)))
        )
    if event.key == pygame.K_PAGEUP:
        return controller.replace_selected_editor(editor.scroll_by(lines=-12))
    if event.key == pygame.K_PAGEDOWN:
        return controller.replace_selected_editor(editor.scroll_by(lines=12))
    if not command and event.unicode and event.unicode.isprintable():
        return controller.replace_selected_editor(editor.insert_text(event.unicode))
    return controller


def _move_editor(editor: EditorState, key: int, modifiers: int) -> EditorState:
    extend = bool(modifiers & pygame.KMOD_SHIFT)
    cursor = editor.cursor_position
    if key == pygame.K_LEFT:
        return editor.move_cursor(
            max(0, editor.cursor_offset - 1), extend_selection=extend
        ).reveal_cursor(12, 40)
    if key == pygame.K_RIGHT:
        return editor.move_cursor(
            min(editor.buffer.character_count, editor.cursor_offset + 1), extend_selection=extend
        ).reveal_cursor(12, 40)
    line = (
        max(1, cursor.line - 1)
        if key == pygame.K_UP
        else min(editor.buffer.line_index.line_count, cursor.line + 1)
    )
    column = min(cursor.column, editor.buffer.line_index.max_column(line))
    return editor.move_to(TextPosition(line, column), extend_selection=extend).reveal_cursor(12, 40)


def _render(
    surface: pygame.Surface, font: BitmapFont, controller: GlasshouseDemoController
) -> None:
    if controller.screen in (GlasshouseDemoScreen.BRIEFING, GlasshouseDemoScreen.WORKBENCH):
        render_glasshouse_workbench(surface, font, controller.workbench)
        _render_footer(surface, font, _workbench_help(controller), controller.notice)
        return
    if controller.screen is GlasshouseDemoScreen.GUIDE:
        render_glasshouse_tutorial(surface, font, controller.tutorial)
        _render_footer(surface, font, "Left/Right lesson | Esc workbench", controller.notice)
        return
    if controller.screen is GlasshouseDemoScreen.MISSION:
        _render_mission(surface, font, controller)
        return
    if controller.screen is GlasshouseDemoScreen.DEBRIEF:
        _render_debrief(surface, font, controller)
        return
    _render_comparison(surface, font, controller)


def _render_mission(
    surface: pygame.Surface, font: BitmapFont, controller: GlasshouseDemoController
) -> None:
    if controller.current_run is None:
        raise AssertionError("Glasshouse mission screen has no run")
    run = controller.current_run.recorded.run
    render_tactical_view(
        surface,
        build_presentation_snapshot(run.state, projectile_events=run.events),
        Camera(pixels_per_millimetre=0.04),
    )
    lines = (
        "GLASSHOUSE CAUSAL DRILL",
        "2 fixed ticks; player requests, simulation resolves.",
        "Lark starts with a 0.5m-uncertainty contact.",
        controller.notice,
    )
    _render_panel(surface, font, lines)
    _render_footer(surface, font, "Enter debrief | C compare | F5 rerun | Esc edit", "")


def _render_debrief(
    surface: pygame.Surface, font: BitmapFont, controller: GlasshouseDemoController
) -> None:
    if controller.current_run is None:
        raise AssertionError("Glasshouse debrief screen has no run")
    surface.fill(_BACKGROUND)
    debrief = controller.current_run.debrief
    if isinstance(debrief, GlasshouseDebrief):
        render_glasshouse_debrief(surface, font, debrief, (8, 8))
        help_text = "R trace source | Esc workbench"
    else:
        _render_panel(
            surface,
            font,
            (
                "GLASSHOUSE DEBRIEF",
                "No injury retained in this controlled run.",
                "The scout did not request the exposed advance.",
            ),
        )
        help_text = "C compare | Esc workbench"
    _render_footer(surface, font, help_text, controller.notice)


def _render_comparison(
    surface: pygame.Surface, font: BitmapFont, controller: GlasshouseDemoController
) -> None:
    if controller.comparison is None:
        raise AssertionError("Glasshouse comparison screen has no comparison")
    surface.fill(_BACKGROUND)
    render_run_comparison_view(surface, font, controller.comparison, (8, 8))
    _render_footer(surface, font, "F5 rerun | Esc workbench", controller.notice)


def _render_panel(surface: pygame.Surface, font: BitmapFont, lines: tuple[str, ...]) -> None:
    line_height = font.measure("M")[1]
    height = len(lines) * line_height + 8
    pygame.draw.rect(surface, _PANEL, (4, 4, surface.get_width() - 8, height))
    pygame.draw.rect(surface, _BORDER, (4, 4, surface.get_width() - 8, height), width=1)
    for index, line in enumerate(lines):
        color = _HEADING if index == 0 else _NOTICE if index == len(lines) - 1 else _NORMAL
        surface.blit(font.render(_truncate(line), color), (8, 8 + index * line_height))


def _render_footer(surface: pygame.Surface, font: BitmapFont, controls: str, notice: str) -> None:
    y = surface.get_height() - _FOOTER_HEIGHT
    pygame.draw.rect(surface, _PANEL, (0, y, surface.get_width(), _FOOTER_HEIGHT))
    pygame.draw.line(surface, _BORDER, (0, y), (surface.get_width(), y))
    text = notice if notice else controls
    color = _NOTICE if notice else _MUTED
    surface.blit(font.render(_truncate(text), color), (4, y + 2))


def _workbench_help(controller: GlasshouseDemoController) -> str:
    if controller.screen is GlasshouseDemoScreen.BRIEFING:
        return "Enter opens workbench | Esc quits"
    return "F1 guide | F2 select 1m | Ctrl+Enter compile | F5 deploy"


def _truncate(text: str) -> str:
    if len(text) <= _MAX_NOTICE_CHARACTERS:
        return text
    return text[: _MAX_NOTICE_CHARACTERS - 3] + "..."
