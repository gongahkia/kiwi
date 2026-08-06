"""pygame-ce shell for the runnable Glasshouse causal-drill usability flow."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.app.glasshouse_demo import (
    GlasshouseColorScheme,
    GlasshouseDemoController,
    GlasshouseDemoScreen,
    GlasshouseInputMode,
)
from kiwi.dsl.source import ByteOffset
from kiwi.render.atlas import TextureAtlas, load_glasshouse_atlas
from kiwi.render.bitmap_font import BitmapFont, load_bitmap_font
from kiwi.render.camera import Camera, Projection, world_to_canvas
from kiwi.render.causal_chain_view import CausalChainPalette
from kiwi.render.challenge_results_view import ChallengeResultsPalette, render_challenge_results
from kiwi.render.glasshouse_debrief_view import (
    GlasshouseDebriefPalette,
    render_glasshouse_debrief,
)
from kiwi.render.glasshouse_tutorial_view import (
    GlasshouseTutorialPalette,
    render_glasshouse_tutorial,
)
from kiwi.render.glasshouse_workbench_view import (
    DEFAULT_GLASSHOUSE_WORKBENCH_PALETTE,
    GlasshouseWorkbenchPalette,
    render_glasshouse_workbench,
)
from kiwi.render.pygame_app import (
    TacticalPalette,
    open_pygame_window,
    present,
    render_tactical_view,
)
from kiwi.render.pygame_lifecycle import quit_pygame
from kiwi.render.run_comparison_view import RunComparisonPalette, render_run_comparison_view
from kiwi.render.source_view import DEFAULT_SOURCE_PALETTE, SourcePalette
from kiwi.sim.snapshot import build_presentation_snapshot
from kiwi.ui.editor import EditorState, TextPosition
from kiwi.ui.glasshouse_debrief import GlasshouseDebrief
from kiwi.ui.timeline import mission_timeline

_BACKGROUND = (10, 14, 19)
_PANEL = (20, 29, 36)
_BORDER = (68, 119, 142)
_HEADING = (111, 216, 238)
_NORMAL = (206, 221, 231)
_NOTICE = (245, 189, 74)
_MUTED = (192, 201, 191)
_FOOTER_HEIGHT = 16
_LOGICAL_SIZE = (960, 540)
_MAX_NOTICE_CHARACTERS = 116
_PREVIEW_STEP_MILLISECONDS = 800
_IMPACT_FEEDBACK_MILLISECONDS = 360
_ATLAS: TextureAtlas | None = None


@dataclass(frozen=True, slots=True)
class GlasshouseDemoPalette:
    """One complete presentation palette for the local causal drill shell."""

    background: tuple[int, int, int]
    panel: tuple[int, int, int]
    border: tuple[int, int, int]
    heading: tuple[int, int, int]
    normal: tuple[int, int, int]
    notice: tuple[int, int, int]
    muted: tuple[int, int, int]
    workbench: GlasshouseWorkbenchPalette
    source: SourcePalette


_CYAN_PALETTE = GlasshouseDemoPalette(
    _BACKGROUND,
    _PANEL,
    _BORDER,
    _HEADING,
    _NORMAL,
    _NOTICE,
    _MUTED,
    DEFAULT_GLASSHOUSE_WORKBENCH_PALETTE,
    DEFAULT_SOURCE_PALETTE,
)
_AMBER_PALETTE = GlasshouseDemoPalette(
    (20, 14, 8),
    (35, 26, 16),
    (178, 129, 61),
    (255, 204, 105),
    (240, 222, 190),
    (255, 156, 82),
    (205, 190, 160),
    GlasshouseWorkbenchPalette(
        background=(20, 14, 8),
        panel=(35, 26, 16),
        border=(178, 129, 61),
        heading=(255, 204, 105),
        normal=(240, 222, 190),
        selected=(255, 222, 132),
        focus=(255, 156, 82),
        muted=(205, 190, 160),
    ),
    SourcePalette(
        default=(240, 222, 190),
        keyword=(255, 204, 105),
        literal=(255, 156, 82),
        identifier=(240, 222, 190),
        operator=(244, 117, 94),
        punctuation=(205, 190, 160),
        invalid=(239, 99, 99),
    ),
)
_PHOSPHOR_PALETTE = GlasshouseDemoPalette(
    (8, 17, 11),
    (13, 31, 20),
    (70, 136, 85),
    (142, 255, 162),
    (213, 239, 216),
    (244, 229, 115),
    (164, 199, 169),
    GlasshouseWorkbenchPalette(
        background=(8, 17, 11),
        panel=(13, 31, 20),
        border=(70, 136, 85),
        heading=(142, 255, 162),
        normal=(213, 239, 216),
        selected=(175, 255, 188),
        focus=(244, 229, 115),
        muted=(164, 199, 169),
    ),
    SourcePalette(
        default=(213, 239, 216),
        keyword=(142, 255, 162),
        literal=(244, 229, 115),
        identifier=(213, 239, 216),
        operator=(255, 143, 117),
        punctuation=(164, 199, 169),
        invalid=(255, 128, 128),
    ),
)
_MAROON_PALETTE = GlasshouseDemoPalette(
    (24, 7, 11),
    (43, 13, 20),
    (143, 53, 69),
    (255, 183, 187),
    (247, 226, 227),
    (238, 139, 77),
    (207, 171, 174),
    GlasshouseWorkbenchPalette(
        background=(24, 7, 11),
        panel=(43, 13, 20),
        border=(143, 53, 69),
        heading=(255, 183, 187),
        normal=(247, 226, 227),
        selected=(255, 204, 142),
        focus=(238, 139, 77),
        muted=(207, 171, 174),
    ),
    SourcePalette(
        default=(247, 226, 227),
        keyword=(255, 183, 187),
        literal=(255, 204, 142),
        identifier=(247, 226, 227),
        operator=(244, 116, 120),
        punctuation=(207, 171, 174),
        invalid=(255, 113, 113),
    ),
)
_WHITE_PALETTE = GlasshouseDemoPalette(
    (242, 239, 232),
    (255, 255, 252),
    (91, 103, 117),
    (23, 37, 54),
    (39, 50, 64),
    (166, 83, 19),
    (103, 113, 124),
    GlasshouseWorkbenchPalette(
        background=(242, 239, 232),
        panel=(255, 255, 252),
        border=(91, 103, 117),
        heading=(23, 37, 54),
        normal=(39, 50, 64),
        selected=(32, 92, 129),
        focus=(166, 83, 19),
        muted=(103, 113, 124),
    ),
    SourcePalette(
        default=(39, 50, 64),
        keyword=(32, 92, 129),
        literal=(166, 83, 19),
        identifier=(39, 50, 64),
        operator=(180, 63, 63),
        punctuation=(103, 113, 124),
        invalid=(190, 44, 44),
    ),
)
_BLACK_PALETTE = GlasshouseDemoPalette(
    (5, 5, 6),
    (17, 17, 19),
    (93, 96, 102),
    (244, 244, 240),
    (211, 211, 205),
    (255, 186, 61),
    (143, 143, 137),
    GlasshouseWorkbenchPalette(
        background=(5, 5, 6),
        panel=(17, 17, 19),
        border=(93, 96, 102),
        heading=(244, 244, 240),
        normal=(211, 211, 205),
        selected=(255, 255, 255),
        focus=(255, 186, 61),
        muted=(143, 143, 137),
    ),
    SourcePalette(
        default=(211, 211, 205),
        keyword=(244, 244, 240),
        literal=(255, 186, 61),
        identifier=(211, 211, 205),
        operator=(255, 129, 129),
        punctuation=(143, 143, 137),
        invalid=(255, 93, 93),
    ),
)
_PALETTES = {
    GlasshouseColorScheme.CYAN: _CYAN_PALETTE,
    GlasshouseColorScheme.AMBER: _AMBER_PALETTE,
    GlasshouseColorScheme.PHOSPHOR: _PHOSPHOR_PALETTE,
    GlasshouseColorScheme.MAROON: _MAROON_PALETTE,
    GlasshouseColorScheme.WHITE: _WHITE_PALETTE,
    GlasshouseColorScheme.BLACK: _BLACK_PALETTE,
}


def run_glasshouse_demo() -> int:
    """Run the local-only Glasshouse usability drill until its window closes."""
    window = open_pygame_window(logical_size=_LOGICAL_SIZE)
    pygame.display.set_caption("Kiwi — Glasshouse causal drill")
    font = load_bitmap_font()
    global _ATLAS
    _ATLAS = load_glasshouse_atlas()
    controller = GlasshouseDemoController.create()
    frame_clock = pygame.time.Clock()
    next_preview_step_at = pygame.time.get_ticks() + _PREVIEW_STEP_MILLISECONDS
    feedback_pulse = controller.preview_feedback_pulse
    feedback_started_at = -_IMPACT_FEEDBACK_MILLISECONDS
    try:
        running = True
        while running:
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                    continue
                if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                    controller = _handle_click(
                        controller,
                        _logical_pointer_position(
                            event.pos, window.window.get_size(), window.logical_size
                        ),
                        font,
                    )
                    should_quit = False
                else:
                    controller, should_quit = _handle_event(controller, event)
                running = running and not should_quit
            now = pygame.time.get_ticks()
            if (
                controller.screen is GlasshouseDemoScreen.LIVE_PREVIEW
                and controller.current_run is not None
                and controller.preview_playing
                and now >= next_preview_step_at
            ):
                controller = controller.advance_preview()
                next_preview_step_at = now + _PREVIEW_STEP_MILLISECONDS
            elif controller.screen is not GlasshouseDemoScreen.LIVE_PREVIEW:
                next_preview_step_at = now + _PREVIEW_STEP_MILLISECONDS
            if controller.preview_feedback_pulse != feedback_pulse:
                feedback_pulse = controller.preview_feedback_pulse
                feedback_started_at = now
            shake_offset, impact_emphasis = _impact_feedback(now - feedback_started_at)
            _render(
                window.logical_canvas,
                font,
                controller,
                shake_offset=shake_offset,
                impact_emphasis=impact_emphasis,
            )
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
        if controller.screen in (GlasshouseDemoScreen.INPUT_SETUP, GlasshouseDemoScreen.BRIEFING):
            return (controller, True)
        return (_escape(controller), False)
    if controller.screen is GlasshouseDemoScreen.INPUT_SETUP:
        if event.key == pygame.K_1:
            return (controller.choose_input_mode(GlasshouseInputMode.STANDARD), False)
        if event.key == pygame.K_2:
            return (controller.choose_input_mode(GlasshouseInputMode.FUNCTION_KEYS), False)
        if event.key in (pygame.K_RETURN, pygame.K_SPACE):
            return (controller.confirm_input_mode(), False)
        return (controller, False)
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
    if controller.screen is GlasshouseDemoScreen.LIVE_PREVIEW:
        return (_handle_live_preview_key(controller, event), False)
    if controller.screen is GlasshouseDemoScreen.MISSION:
        if event.key in (pygame.K_RETURN, pygame.K_d):
            return (controller.open_debrief(), False)
        if event.key == pygame.K_c:
            return (controller.open_comparison(), False)
        if event.key == pygame.K_h:
            return (controller.open_results(), False)
        if _deploy_pressed(controller, event):
            return (controller.return_to_workbench().deploy(), False)
        return (controller, False)
    if controller.screen is GlasshouseDemoScreen.DEBRIEF:
        if event.key == pygame.K_r:
            return (controller.guide_revision(), False)
        if event.key == pygame.K_h:
            return (controller.open_results(), False)
        return (controller, False)
    if controller.screen is GlasshouseDemoScreen.RESULTS:
        return (controller, False)
    if controller.screen is GlasshouseDemoScreen.COMPARISON and _deploy_pressed(controller, event):
        return (controller.return_to_workbench().deploy(), False)
    return (controller, False)


def _escape(controller: GlasshouseDemoController) -> GlasshouseDemoController:
    if controller.screen in (GlasshouseDemoScreen.INPUT_SETUP, GlasshouseDemoScreen.BRIEFING):
        return controller
    if controller.screen is GlasshouseDemoScreen.GUIDE:
        return controller.close_guide()
    return controller.return_to_workbench()


def _handle_workbench_key(
    controller: GlasshouseDemoController, event: pygame.event.Event
) -> GlasshouseDemoController:
    modifiers = event.mod
    command = modifiers & (pygame.KMOD_CTRL | pygame.KMOD_META)
    shifted = modifiers & pygame.KMOD_SHIFT
    if event.key == pygame.K_F1 or (
        controller.input_mode is GlasshouseInputMode.STANDARD
        and command
        and event.key == pygame.K_g
    ):
        return controller.open_guide()
    if event.key == pygame.K_F2 or (
        controller.input_mode is GlasshouseInputMode.STANDARD
        and command
        and not shifted
        and event.key == pygame.K_t
    ):
        return controller.select_scout_threshold()
    if event.key == pygame.K_F3 or (
        controller.input_mode is GlasshouseInputMode.STANDARD
        and command
        and shifted
        and event.key == pygame.K_t
    ):
        return controller.cycle_color_scheme()
    if _deploy_pressed(controller, event):
        return controller.deploy()
    if event.key == pygame.K_TAB:
        completed = controller.accept_completion()
        if completed is not controller:
            return completed
        direction = -1 if shifted else 1
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


def _handle_live_preview_key(
    controller: GlasshouseDemoController, event: pygame.event.Event
) -> GlasshouseDemoController:
    modifiers = event.mod
    command = modifiers & (pygame.KMOD_CTRL | pygame.KMOD_META)
    if event.key in (pygame.K_RETURN, pygame.K_d):
        return controller.open_debrief()
    if event.key == pygame.K_h:
        return controller.open_results()
    if _deploy_pressed(controller, event):
        return controller.deploy()
    if command and event.key == pygame.K_l:
        return controller.toggle_hot_reload()
    if command and event.key == pygame.K_p:
        return controller.toggle_preview_playing()
    if command and event.key == pygame.K_PERIOD:
        return controller.advance_preview().pause_preview()
    if event.key in (pygame.K_q, pygame.K_e):
        return controller.rotate_preview(-1 if event.key == pygame.K_q else 1)
    zoom_direction = _preview_zoom_direction(event)
    if zoom_direction is not None:
        return controller.zoom_preview(zoom_direction)
    return _handle_workbench_key(controller, event)


def _preview_zoom_direction(event: pygame.event.Event) -> int | None:
    """Map main and keypad plus/minus input to one presentation zoom direction."""
    if event.key == pygame.K_KP_PLUS or event.unicode == "+":
        return 1
    if event.key in (pygame.K_KP_MINUS, pygame.K_MINUS) or event.unicode == "-":
        return -1
    return None


def _deploy_pressed(controller: GlasshouseDemoController, event: pygame.event.Event) -> bool:
    """Return whether one platform-selected deployment shortcut was pressed."""
    if event.key == pygame.K_F5:
        return True
    modifiers = event.mod
    return bool(
        controller.input_mode is GlasshouseInputMode.STANDARD
        and modifiers & (pygame.KMOD_CTRL | pygame.KMOD_META)
        and event.key == pygame.K_r
    )


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
    surface: pygame.Surface,
    font: BitmapFont,
    controller: GlasshouseDemoController,
    *,
    shake_offset: tuple[int, int] = (0, 0),
    impact_emphasis: int = 0,
) -> None:
    palette = _palette_for(controller.color_scheme)
    if controller.screen is GlasshouseDemoScreen.INPUT_SETUP:
        _render_input_setup(surface, font, controller)
        return
    if controller.screen in (GlasshouseDemoScreen.BRIEFING, GlasshouseDemoScreen.WORKBENCH):
        render_glasshouse_workbench(
            surface,
            font,
            controller.workbench,
            palette=palette.workbench,
            source_palette=palette.source,
            completions=controller.completions(),
        )
        if controller.screen is GlasshouseDemoScreen.WORKBENCH:
            _render_workbench_controls(surface, font, controller, palette)
        _render_footer(surface, font, _workbench_help(controller), controller.notice, palette)
        return
    if controller.screen is GlasshouseDemoScreen.GUIDE:
        render_glasshouse_tutorial(
            surface,
            font,
            controller.tutorial,
            palette=GlasshouseTutorialPalette(
                palette.background,
                palette.heading,
                palette.workbench.selected,
                palette.normal,
                palette.notice,
            ),
        )
        _render_footer(
            surface,
            font,
            "Left/Right lesson | Esc workbench",
            controller.notice,
            palette,
        )
        return
    if controller.screen is GlasshouseDemoScreen.LIVE_PREVIEW:
        _render_live_preview(
            surface,
            font,
            controller,
            palette,
            shake_offset=shake_offset,
            impact_emphasis=impact_emphasis,
        )
        return
    if controller.screen is GlasshouseDemoScreen.MISSION:
        _render_mission(surface, font, controller, palette)
        return
    if controller.screen is GlasshouseDemoScreen.DEBRIEF:
        _render_debrief(surface, font, controller, palette)
        return
    if controller.screen is GlasshouseDemoScreen.RESULTS:
        _render_results(surface, font, controller, palette)
        return
    _render_comparison(surface, font, controller, palette)


def _render_live_preview(
    surface: pygame.Surface,
    font: BitmapFont,
    controller: GlasshouseDemoController,
    palette: GlasshouseDemoPalette,
    *,
    shake_offset: tuple[int, int],
    impact_emphasis: int,
) -> None:
    left_rect, right_rect = _live_preview_panes(surface)
    left = surface.subsurface(left_rect)
    right = surface.subsurface(right_rect)
    render_glasshouse_workbench(
        left,
        font,
        controller.workbench,
        palette=palette.workbench,
        source_palette=palette.source,
        compact_sidebar=True,
        completions=controller.completions(),
    )
    _render_workbench_controls(left, font, controller, palette)
    _render_preview_map(
        right,
        font,
        controller,
        palette,
        shake_offset=shake_offset,
        impact_emphasis=impact_emphasis,
    )
    _render_footer(
        surface,
        font,
        "Click controls | Cmd+P pause | Cmd+. step | Q/E rotate | +/- zoom | D debrief",
        controller.notice,
        palette,
    )


def _render_preview_map(
    surface: pygame.Surface,
    font: BitmapFont,
    controller: GlasshouseDemoController,
    palette: GlasshouseDemoPalette,
    *,
    shake_offset: tuple[int, int] = (0, 0),
    impact_emphasis: int = 0,
) -> None:
    if controller.current_run is None:
        surface.fill(palette.background)
        _render_preview_panel(
            surface,
            font,
            (
                "LIVE PREVIEW BLOCKED",
                "Fix the compile diagnostic on the left.",
                "The last valid run is not shown as current code.",
            ),
            palette,
        )
        _render_preview_controls(surface, font, controller, palette)
        return
    snapshot = controller.current_run.snapshots[controller.preview_snapshot_index]
    render_tactical_view(
        surface,
        snapshot,
        _preview_camera(controller, shake_offset),
        palette=_tactical_palette(palette),
        atlas=_ATLAS,
        impact_emphasis=impact_emphasis,
    )
    trace_lines = _preview_trace_lines(controller, snapshot.tick)
    _render_preview_panel(
        surface,
        font,
        (
            (
                f"PREVIEW STALE  checkpoint t{snapshot.tick}"
                if controller.preview_stale
                else f"LIVE PREVIEW  checkpoint t{snapshot.tick}"
            ),
            *trace_lines,
        ),
        palette,
    )
    _render_preview_controls(surface, font, controller, palette)


def _preview_trace_lines(
    controller: GlasshouseDemoController, snapshot_tick: int
) -> tuple[str, ...]:
    if controller.current_run is None:
        return ()
    if controller.preview_stale:
        return ("source changed; Compile + run is required to refresh.",)
    if snapshot_tick == 0:
        return (
            "initial state; next step evaluates the scout policy",
            "TRY: type 0 to stop Lark's exposed advance.",
            "DSL policies run once per fixed tick; no unbounded loops.",
        )
    trace_tick = snapshot_tick - 1
    entries = tuple(
        entry
        for entry in mission_timeline(controller.current_run.trace).entries
        if entry.tick == trace_tick
    )
    if not entries:
        return (f"t{trace_tick}: no retained trace entries",)
    rows = tuple(
        _truncate(f"t{entry.tick} {entry.kind.value}: {entry.summary}") for entry in entries[:3]
    )
    return rows + ("yellow source selection = emitted intention origin",)


def _preview_camera(
    controller: GlasshouseDemoController,
    screen_offset: tuple[int, int] = (0, 0),
) -> Camera:
    """Build one renderer-only isometric preview camera from controller UI state."""
    return Camera(
        pixels_per_millimetre=0.027 * controller.preview_zoom_percent / 100,
        projection=Projection.ISOMETRIC,
        rotation_quarters=controller.preview_rotation_quarters,
        screen_offset_x=screen_offset[0],
        screen_offset_y=screen_offset[1],
    )


def _impact_feedback(elapsed_milliseconds: int) -> tuple[tuple[int, int], int]:
    """Return a deterministic decaying camera kick and impact flash strength."""
    if (
        not isinstance(elapsed_milliseconds, int)
        or isinstance(elapsed_milliseconds, bool)
        or elapsed_milliseconds < 0
        or elapsed_milliseconds >= _IMPACT_FEEDBACK_MILLISECONDS
    ):
        return ((0, 0), 0)
    magnitude = 1 + (_IMPACT_FEEDBACK_MILLISECONDS - elapsed_milliseconds) * 3 // (
        _IMPACT_FEEDBACK_MILLISECONDS
    )
    direction = ((-1, 1), (1, -1), (-1, 0), (1, 1))[elapsed_milliseconds // 45 % 4]
    return ((direction[0] * magnitude, direction[1] * magnitude), magnitude)


def _render_preview_panel(
    surface: pygame.Surface,
    font: BitmapFont,
    lines: tuple[str, ...],
    palette: GlasshouseDemoPalette,
) -> None:
    line_height = font.measure("M")[1]
    height = len(lines) * line_height + 8
    pygame.draw.rect(surface, palette.panel, (4, 4, surface.get_width() - 8, height))
    pygame.draw.rect(surface, palette.border, (4, 4, surface.get_width() - 8, height), width=1)
    for index, line in enumerate(lines):
        color = (
            palette.heading
            if index == 0
            else palette.notice
            if "intention" in line
            else palette.normal
        )
        surface.blit(
            font.render(_fit_text(font, _truncate(line), surface.get_width() - 16), color),
            (8, 8 + index * line_height),
        )


def _render_preview_controls(
    surface: pygame.Surface,
    font: BitmapFont,
    controller: GlasshouseDemoController,
    palette: GlasshouseDemoPalette,
) -> None:
    play_button, step_button, reload_button, debrief_button = _preview_buttons(surface, font)
    _render_button(
        surface,
        font,
        play_button,
        "Pause" if controller.preview_playing else "Play",
        controller.preview_playing,
        palette,
    )
    _render_button(surface, font, step_button, "Step", False, palette)
    _render_button(
        surface,
        font,
        reload_button,
        f"Hot reload {'on' if controller.hot_reload_enabled else 'off'}",
        controller.hot_reload_enabled,
        palette,
    )
    _render_button(surface, font, debrief_button, "Debrief", False, palette)


def _live_preview_panes(surface: pygame.Surface) -> tuple[pygame.Rect, pygame.Rect]:
    width, height = surface.get_size()
    body_height = height - _FOOTER_HEIGHT
    left_width = width * 11 // 20
    return (
        pygame.Rect(0, 0, left_width, body_height),
        pygame.Rect(left_width, 0, width - left_width, body_height),
    )


def _render_mission(
    surface: pygame.Surface,
    font: BitmapFont,
    controller: GlasshouseDemoController,
    palette: GlasshouseDemoPalette,
) -> None:
    if controller.current_run is None:
        raise AssertionError("Glasshouse mission screen has no run")
    run = controller.current_run.recorded.run
    render_tactical_view(
        surface,
        build_presentation_snapshot(run.state, projectile_events=run.events),
        _preview_camera(controller),
        palette=_tactical_palette(palette),
        atlas=_ATLAS,
    )
    lines = (
        "GLASSHOUSE CAUSAL DRILL",
        "2 fixed ticks; player requests, simulation resolves.",
        "Lark starts with a 0.5m-uncertainty contact.",
        controller.notice,
    )
    _render_panel(surface, font, lines, palette)
    _render_footer(
        surface,
        font,
        f"Enter debrief | C compare | H results | {_deploy_label(controller)} rerun | Esc edit",
        "",
        palette,
    )


def _render_debrief(
    surface: pygame.Surface,
    font: BitmapFont,
    controller: GlasshouseDemoController,
    palette: GlasshouseDemoPalette,
) -> None:
    if controller.current_run is None:
        raise AssertionError("Glasshouse debrief screen has no run")
    surface.fill(palette.background)
    debrief = controller.current_run.debrief
    if isinstance(debrief, GlasshouseDebrief):
        render_glasshouse_debrief(
            surface,
            font,
            debrief,
            (8, 8),
            palette=GlasshouseDebriefPalette(
                palette.heading,
                palette.normal,
                palette.notice,
            ),
            chain_palette=CausalChainPalette(
                palette.normal,
                palette.heading,
                palette.notice,
                palette.muted,
            ),
        )
        help_text = "R trace source | H results | Esc workbench"
    else:
        _render_panel(
            surface,
            font,
            (
                "GLASSHOUSE DEBRIEF",
                "No injury retained in this controlled run.",
                "The scout did not request the exposed advance.",
            ),
            palette,
        )
        help_text = "C compare | H results | Esc workbench"
    _render_footer(surface, font, help_text, controller.notice, palette)


def _render_comparison(
    surface: pygame.Surface,
    font: BitmapFont,
    controller: GlasshouseDemoController,
    palette: GlasshouseDemoPalette,
) -> None:
    if controller.comparison is None:
        raise AssertionError("Glasshouse comparison screen has no comparison")
    surface.fill(palette.background)
    render_run_comparison_view(
        surface,
        font,
        controller.comparison,
        (8, 8),
        palette=RunComparisonPalette(
            palette.heading,
            palette.normal,
            palette.notice,
            palette.source.invalid,
        ),
    )
    _render_footer(
        surface,
        font,
        f"H results | {_deploy_label(controller)} rerun | Esc workbench",
        controller.notice,
        palette,
    )


def _render_results(
    surface: pygame.Surface,
    font: BitmapFont,
    controller: GlasshouseDemoController,
    palette: GlasshouseDemoPalette,
) -> None:
    if not controller.result_history.results:
        raise AssertionError("Glasshouse result screen requires a completed local attempt")
    render_challenge_results(
        surface,
        font,
        controller.result_history,
        controller.result_history.results[-1],
        ChallengeResultsPalette(
            palette.background,
            palette.panel,
            palette.border,
            palette.heading,
            palette.normal,
            palette.workbench.selected,
            palette.source.invalid,
            palette.notice,
        ),
    )
    _render_footer(surface, font, "Esc workbench", controller.notice, palette)


def _render_panel(
    surface: pygame.Surface,
    font: BitmapFont,
    lines: tuple[str, ...],
    palette: GlasshouseDemoPalette = _CYAN_PALETTE,
) -> None:
    line_height = font.measure("M")[1]
    height = len(lines) * line_height + 8
    pygame.draw.rect(surface, palette.panel, (4, 4, surface.get_width() - 8, height))
    pygame.draw.rect(surface, palette.border, (4, 4, surface.get_width() - 8, height), width=1)
    for index, line in enumerate(lines):
        color = (
            palette.heading
            if index == 0
            else palette.notice
            if index == len(lines) - 1
            else palette.normal
        )
        surface.blit(
            font.render(_fit_text(font, _truncate(line), surface.get_width() - 16), color),
            (8, 8 + index * line_height),
        )


def _render_footer(
    surface: pygame.Surface,
    font: BitmapFont,
    controls: str,
    notice: str,
    palette: GlasshouseDemoPalette = _CYAN_PALETTE,
) -> None:
    y = surface.get_height() - _FOOTER_HEIGHT
    pygame.draw.rect(surface, palette.panel, (0, y, surface.get_width(), _FOOTER_HEIGHT))
    pygame.draw.line(surface, palette.border, (0, y), (surface.get_width(), y))
    text = notice if notice else controls
    color = palette.notice if notice else palette.muted
    surface.blit(
        font.render(_fit_text(font, _truncate(text), surface.get_width() - 8), color),
        (4, y + 2),
    )


def _workbench_help(controller: GlasshouseDemoController) -> str:
    if controller.screen is GlasshouseDemoScreen.BRIEFING:
        return "Enter opens workbench | Esc quits"
    if controller.input_mode is GlasshouseInputMode.STANDARD:
        return "Cmd+T select 1m | Cmd+Shift+T theme | Tab complete | Cmd+R deploy"
    return "F2 select 1m | F3 theme | Tab complete | F5 deploy"


def _deploy_label(controller: GlasshouseDemoController) -> str:
    """Return the selected deployment shortcut label for a non-editing screen."""
    return "Cmd+R" if controller.input_mode is GlasshouseInputMode.STANDARD else "F5"


def _platform_label(platform_name: str) -> str:
    """Return one compact runtime platform label for input setup."""
    return {"Darwin": "macOS", "Windows": "Windows", "Linux": "Linux"}.get(
        platform_name, platform_name
    )


def _input_mode_label(input_mode: GlasshouseInputMode) -> str:
    """Return one compact selected input-mode label."""
    return "standard keys" if input_mode is GlasshouseInputMode.STANDARD else "function keys"


def _render_input_setup(
    surface: pygame.Surface, font: BitmapFont, controller: GlasshouseDemoController
) -> None:
    surface.fill(_BACKGROUND)
    line_height = font.measure("M")[1]
    lines = (
        "INPUT SETUP",
        (
            f"{_platform_label(controller.detected_platform)} detected: "
            f"{_input_mode_label(controller.input_mode)} selected."
        ),
        "Choose a key set before the causal drill starts.",
    )
    for index, line in enumerate(lines):
        color = _HEADING if index == 0 else _NORMAL
        surface.blit(font.render(line, color), (24, 24 + index * line_height))
    standard, function_keys, continue_button = _input_setup_buttons(surface, font)
    _render_button(
        surface,
        font,
        standard,
        "1  Standard keys: Cmd+G / Cmd+T / Cmd+Enter / Cmd+R",
        controller.input_mode is GlasshouseInputMode.STANDARD,
    )
    _render_button(
        surface,
        font,
        function_keys,
        "2  Function keys: F1 / F2 / Cmd+Enter / F5",
        controller.input_mode is GlasshouseInputMode.FUNCTION_KEYS,
    )
    _render_button(surface, font, continue_button, "Continue", True)
    _render_footer(surface, font, "Click a key set | Enter continues | Esc quits", "")


def _render_workbench_controls(
    surface: pygame.Surface,
    font: BitmapFont,
    controller: GlasshouseDemoController,
    palette: GlasshouseDemoPalette = _CYAN_PALETTE,
) -> None:
    compile_button, deploy_button = _workbench_buttons(surface, font)
    theme_button = _theme_button(surface, font)
    _render_button(
        surface, font, theme_button, f"Theme: {controller.color_scheme.value}", False, palette
    )
    _render_button(surface, font, compile_button, "Compile", False, palette)
    _render_button(surface, font, deploy_button, "Compile + run", True, palette)
    if pygame.time.get_ticks() // 500 % 2 == 0:
        _render_editor_caret(surface, font, controller, palette)


def _render_button(
    surface: pygame.Surface,
    font: BitmapFont,
    rect: pygame.Rect,
    label: str,
    emphasized: bool,
    palette: GlasshouseDemoPalette = _CYAN_PALETTE,
) -> None:
    fill = palette.border if emphasized else palette.panel
    text_color = palette.background if emphasized else palette.heading
    pygame.draw.rect(surface, fill, rect)
    pygame.draw.rect(surface, palette.heading, rect, width=1)
    label_surface = font.render(label, text_color)
    surface.blit(
        label_surface,
        (rect.x + max(4, (rect.width - label_surface.get_width()) // 2), rect.y + 3),
    )


def _render_editor_caret(
    surface: pygame.Surface,
    font: BitmapFont,
    controller: GlasshouseDemoController,
    palette: GlasshouseDemoPalette = _CYAN_PALETTE,
) -> None:
    _, source_rect, _ = _workbench_rects(surface, font)
    editor = controller.workbench.editor
    cursor = editor.cursor_position
    first_visible_line = editor.scroll.line
    if cursor.line < first_visible_line:
        return
    y = source_rect.y + 4 + (cursor.line - first_visible_line) * font.measure("M")[1]
    if y + font.measure("M")[1] > source_rect.bottom - 4:
        return
    line = editor.buffer.line_text(cursor.line)
    gutter_width = font.measure(str(editor.buffer.line_index.line_count))[0] + 12
    x = source_rect.x + gutter_width + 4 + font.measure(line[: cursor.column - 1].expandtabs(4))[0]
    if x >= source_rect.right - font.measure("M")[0]:
        return
    previous_clip = surface.get_clip()
    surface.set_clip(source_rect.inflate(-8, -8))
    surface.blit(font.render("_", palette.notice), (x, y))
    surface.set_clip(previous_clip)


def _input_setup_buttons(
    surface: pygame.Surface, font: BitmapFont
) -> tuple[pygame.Rect, pygame.Rect, pygame.Rect]:
    width, _ = surface.get_size()
    line_height = font.measure("M")[1]
    button_width = width - 48
    return (
        pygame.Rect(24, 78, button_width, line_height + 10),
        pygame.Rect(24, 112, button_width, line_height + 10),
        pygame.Rect(24, 158, max(108, font.measure("Continue")[0] + 12), line_height + 10),
    )


def _workbench_rects(
    surface: pygame.Surface, font: BitmapFont
) -> tuple[pygame.Rect, pygame.Rect, pygame.Rect]:
    width, height = surface.get_size()
    line_height = font.measure("M")[1]
    sidebar_width = max(140, width // 4)
    output_height = max(line_height * 4, height // 4)
    return (
        pygame.Rect(8, 8, sidebar_width - 12, height - output_height - 20),
        pygame.Rect(
            sidebar_width + 8,
            line_height + 12,
            width - sidebar_width - 16,
            height - output_height - line_height - 20,
        ),
        pygame.Rect(8, height - output_height - 8, width - 16, output_height),
    )


def _workbench_buttons(
    surface: pygame.Surface, font: BitmapFont
) -> tuple[pygame.Rect, pygame.Rect]:
    _, _, output_rect = _workbench_rects(surface, font)
    line_height = font.measure("M")[1]
    deploy_width = font.measure("Compile + run")[0] + 12
    compile_width = font.measure("Compile")[0] + 12
    y = output_rect.bottom - line_height - 6
    deploy = pygame.Rect(output_rect.right - deploy_width - 5, y, deploy_width, line_height + 4)
    compile = pygame.Rect(deploy.left - compile_width - 6, y, compile_width, line_height + 4)
    return (compile, deploy)


def _theme_button(surface: pygame.Surface, font: BitmapFont) -> pygame.Rect:
    """Return the fixed-width palette selector beside the compile controls."""
    compile_button, _ = _workbench_buttons(surface, font)
    line_height = font.measure("M")[1]
    width = font.measure("Theme: phosphor")[0] + 12
    return pygame.Rect(
        compile_button.left - width - 6,
        compile_button.y,
        width,
        line_height + 4,
    )


def _preview_buttons(
    surface: pygame.Surface, font: BitmapFont
) -> tuple[pygame.Rect, pygame.Rect, pygame.Rect, pygame.Rect]:
    line_height = font.measure("M")[1]
    labels = ("Pause", "Step", "Hot reload off", "Debrief")
    widths = tuple(font.measure(label)[0] + 12 for label in labels)
    y = surface.get_height() - line_height - 6
    x = 6
    rects: list[pygame.Rect] = []
    for width in widths:
        rects.append(pygame.Rect(x, y, width, line_height + 4))
        x += width + 5
    return (rects[0], rects[1], rects[2], rects[3])


def _handle_click(
    controller: GlasshouseDemoController, position: tuple[int, int], font: BitmapFont
) -> GlasshouseDemoController:
    if controller.screen is GlasshouseDemoScreen.INPUT_SETUP:
        standard, function_keys, continue_button = _input_setup_buttons(
            pygame.Surface(_LOGICAL_SIZE), font
        )
        if standard.collidepoint(position):
            return controller.choose_input_mode(GlasshouseInputMode.STANDARD)
        if function_keys.collidepoint(position):
            return controller.choose_input_mode(GlasshouseInputMode.FUNCTION_KEYS)
        if continue_button.collidepoint(position):
            return controller.confirm_input_mode()
        return controller
    if controller.screen is GlasshouseDemoScreen.WORKBENCH:
        return _handle_workbench_click(controller, position, font, _LOGICAL_SIZE)
    if controller.screen is GlasshouseDemoScreen.LIVE_PREVIEW:
        logical_surface = pygame.Surface(_LOGICAL_SIZE)
        left_rect, right_rect = _live_preview_panes(logical_surface)
        if left_rect.collidepoint(position):
            return _handle_workbench_click(
                controller,
                position,
                font,
                (left_rect.width, left_rect.height),
            )
        if right_rect.collidepoint(position):
            local_position = (position[0] - right_rect.x, position[1] - right_rect.y)
            return _handle_preview_click(
                controller,
                local_position,
                font,
                (right_rect.width, right_rect.height),
            )
        return controller
    return controller


def _handle_workbench_click(
    controller: GlasshouseDemoController,
    position: tuple[int, int],
    font: BitmapFont,
    canvas_size: tuple[int, int],
) -> GlasshouseDemoController:
    surface = pygame.Surface(canvas_size)
    sidebar_rect, source_rect, _ = _workbench_rects(surface, font)
    compile_button, deploy_button = _workbench_buttons(surface, font)
    theme_button = _theme_button(surface, font)
    if compile_button.collidepoint(position):
        return controller.compile_selected()
    if deploy_button.collidepoint(position):
        return controller.deploy()
    if theme_button.collidepoint(position):
        return controller.cycle_color_scheme()
    if sidebar_rect.collidepoint(position):
        line_height = font.measure("M")[1]
        policy_index = (position[1] - 16) // line_height - 1
        if 0 <= policy_index < len(controller.workbench.policies):
            return controller.select_policy_index(policy_index)
        return controller
    if source_rect.collidepoint(position):
        return _move_editor_to_pointer(controller, position, source_rect, font)
    return controller


def _handle_preview_click(
    controller: GlasshouseDemoController,
    position: tuple[int, int],
    font: BitmapFont,
    canvas_size: tuple[int, int],
) -> GlasshouseDemoController:
    surface = pygame.Surface(canvas_size)
    play_button, step_button, reload_button, debrief_button = _preview_buttons(surface, font)
    if play_button.collidepoint(position):
        return controller.toggle_preview_playing()
    if step_button.collidepoint(position):
        return controller.advance_preview().pause_preview()
    if reload_button.collidepoint(position):
        return controller.toggle_hot_reload()
    if debrief_button.collidepoint(position):
        return controller.open_debrief()
    if controller.current_run is None:
        return controller
    snapshot = controller.current_run.snapshots[controller.preview_snapshot_index]
    candidates = tuple(
        (
            operative.entity_id,
            world_to_canvas(operative.position, canvas_size, _preview_camera(controller)),
        )
        for operative in snapshot.operatives
    )
    if not candidates:
        return controller
    entity_id, point = min(
        candidates,
        key=lambda candidate: (
            (candidate[1][0] - position[0]) ** 2 + (candidate[1][1] - position[1]) ** 2,
            candidate[0],
        ),
    )
    if (point[0] - position[0]) ** 2 + (point[1] - position[1]) ** 2 <= 16**2:
        return controller.select_preview_entity(entity_id)
    return controller


def _move_editor_to_pointer(
    controller: GlasshouseDemoController,
    position: tuple[int, int],
    source_rect: pygame.Rect,
    font: BitmapFont,
) -> GlasshouseDemoController:
    editor = controller.workbench.editor
    line_height = font.measure("M")[1]
    line = min(
        editor.buffer.line_index.line_count,
        editor.scroll.line + max(0, (position[1] - source_rect.y - 4) // line_height),
    )
    character_width = font.measure("M")[0]
    gutter_width = font.measure(str(editor.buffer.line_index.line_count))[0] + 12
    source_x = source_rect.x + gutter_width + 4
    column = min(
        editor.buffer.line_index.max_column(line),
        max(1, (position[0] - source_x) // character_width + 1),
    )
    rows = max(1, (source_rect.height - 8) // line_height)
    columns = max(1, (source_rect.width - gutter_width - 8) // character_width)
    updated = controller.replace_selected_editor(
        editor.move_to(TextPosition(line, column)).reveal_cursor(rows, columns)
    )
    if updated.screen is not GlasshouseDemoScreen.LIVE_PREVIEW:
        return updated
    source = updated.workbench.source.text
    return updated.select_preview_source_offset(
        ByteOffset(len(source[: updated.workbench.editor.cursor_offset].encode("utf-8")))
    )


def _logical_pointer_position(
    position: tuple[int, int], window_size: tuple[int, int], logical_size: tuple[int, int]
) -> tuple[int, int]:
    """Convert one physical pygame pointer position to the logical canvas grid."""
    if window_size[0] <= 0 or window_size[1] <= 0:
        raise ValueError("pygame window dimensions must be positive")
    return (
        position[0] * logical_size[0] // window_size[0],
        position[1] * logical_size[1] // window_size[1],
    )


def _truncate(text: str) -> str:
    if len(text) <= _MAX_NOTICE_CHARACTERS:
        return text
    return text[: _MAX_NOTICE_CHARACTERS - 3] + "..."


def _fit_text(font: BitmapFont, text: str, width: int) -> str:
    """Return one bitmap-font line that fits an inclusive presentation width."""
    if width <= 0:
        raise ValueError("Glasshouse text width must be positive")
    if font.measure(text)[0] <= width:
        return text
    suffix = "..."
    if font.measure(suffix)[0] > width:
        return ""
    end = len(text)
    while end > 0 and font.measure(text[:end] + suffix)[0] > width:
        end -= 1
    return text[:end] + suffix if end > 0 else suffix


def _palette_for(color_scheme: GlasshouseColorScheme) -> GlasshouseDemoPalette:
    """Return the explicit presentation palette for one controller scheme."""
    if not isinstance(color_scheme, GlasshouseColorScheme):
        raise TypeError("Glasshouse color scheme is invalid")
    return _PALETTES[color_scheme]


def _tactical_palette(palette: GlasshouseDemoPalette) -> TacticalPalette:
    """Project the active terminal theme across the renderer-only tactical view."""
    if not isinstance(palette, GlasshouseDemoPalette):
        raise TypeError("Glasshouse tactical palette requires a demo palette")
    return TacticalPalette(
        background=palette.background,
        map_fill=palette.panel,
        map_border=palette.border,
        obstacle=palette.muted,
        path=palette.notice,
        operative=palette.workbench.selected,
        hostile=palette.source.operator,
        objective=palette.notice,
        visibility=palette.border,
        visible_geometry=palette.heading,
        contact=palette.notice,
        contact_uncertainty=palette.source.operator,
        projectile=palette.notice,
        impact=palette.source.operator,
        cover_low=palette.notice,
        cover_high=palette.workbench.selected,
        cover_damaged=palette.source.invalid,
    )
