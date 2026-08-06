"""Bitmap rendering for the non-authoritative Glasshouse briefing and workbench."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.dsl.source import ByteOffset, SourceFile
from kiwi.render.bitmap_font import BitmapFont
from kiwi.render.compile_output_view import render_compile_output_panel
from kiwi.render.diagnostics_view import render_diagnostic_panel, render_inline_diagnostics
from kiwi.render.source_view import render_source
from kiwi.ui.glasshouse_workbench import GlasshouseFlowPhase, GlasshouseWorkbench


def _validate_color(color: tuple[int, int, int]) -> None:
    if not isinstance(color, tuple) or len(color) != 3:
        raise ValueError("Glasshouse workbench palette color must be an RGB tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in color):
        raise ValueError("Glasshouse workbench palette color components must be integers")
    if any(component < 0 or component > 255 for component in color):
        raise ValueError("Glasshouse workbench palette color components must be 0 through 255")


@dataclass(frozen=True, slots=True)
class GlasshouseWorkbenchPalette:
    """Fixed restrained tactical-terminal colours for the Glasshouse flow."""

    background: tuple[int, int, int] = (10, 14, 19)
    panel: tuple[int, int, int] = (20, 29, 36)
    border: tuple[int, int, int] = (68, 119, 142)
    heading: tuple[int, int, int] = (111, 216, 238)
    normal: tuple[int, int, int] = (206, 221, 231)
    selected: tuple[int, int, int] = (111, 216, 168)
    focus: tuple[int, int, int] = (245, 189, 74)
    muted: tuple[int, int, int] = (192, 201, 191)

    def __post_init__(self) -> None:
        for color in (
            self.background,
            self.panel,
            self.border,
            self.heading,
            self.normal,
            self.selected,
            self.focus,
            self.muted,
        ):
            _validate_color(color)


DEFAULT_GLASSHOUSE_WORKBENCH_PALETTE = GlasshouseWorkbenchPalette()


@dataclass(frozen=True, slots=True)
class GlasshouseWorkbenchRenderResult:
    """The rendered phase and logical rows for a single non-authoritative frame."""

    phase: GlasshouseFlowPhase
    line_count: int

    def __post_init__(self) -> None:
        if not isinstance(self.phase, GlasshouseFlowPhase):
            raise TypeError("Glasshouse workbench render phase is invalid")
        if not isinstance(self.line_count, int) or isinstance(self.line_count, bool):
            raise TypeError("Glasshouse workbench render line count must be an integer")
        if self.line_count <= 0:
            raise ValueError("Glasshouse workbench render line count must be positive")


def render_glasshouse_workbench(
    surface: pygame.Surface,
    font: BitmapFont,
    workbench: GlasshouseWorkbench,
    *,
    scale: int = 1,
    palette: GlasshouseWorkbenchPalette = DEFAULT_GLASSHOUSE_WORKBENCH_PALETTE,
    compact_sidebar: bool = False,
) -> GlasshouseWorkbenchRenderResult:
    """Render briefing or source-review state without changing editor or authority state."""
    if not isinstance(surface, pygame.Surface):
        raise TypeError("Glasshouse workbench rendering requires a pygame surface")
    if not isinstance(font, BitmapFont):
        raise TypeError("Glasshouse workbench rendering requires a bitmap font")
    if not isinstance(workbench, GlasshouseWorkbench):
        raise TypeError("Glasshouse workbench rendering requires workbench state")
    if not isinstance(scale, int) or isinstance(scale, bool) or scale < 1:
        raise ValueError("Glasshouse workbench render scale must be positive")
    if not isinstance(palette, GlasshouseWorkbenchPalette):
        raise TypeError("Glasshouse workbench render palette is invalid")
    if not isinstance(compact_sidebar, bool):
        raise TypeError("Glasshouse workbench compact sidebar flag must be boolean")
    surface.fill(palette.background)
    if workbench.phase is GlasshouseFlowPhase.BRIEFING:
        return _render_briefing(surface, font, workbench, scale, palette)
    return _render_workbench(surface, font, workbench, scale, palette, compact_sidebar)


def _render_briefing(
    surface: pygame.Surface,
    font: BitmapFont,
    workbench: GlasshouseWorkbench,
    scale: int,
    palette: GlasshouseWorkbenchPalette,
) -> GlasshouseWorkbenchRenderResult:
    lines = workbench.briefing.panel_lines
    line_height = font.measure("M", scale)[1]
    for index, line in enumerate(lines):
        if line == "OPEN KIWI WORKBENCH":
            color = palette.selected
        elif index == 0 or line.isupper():
            color = palette.heading
        else:
            color = palette.normal
        surface.blit(font.render(line, color, scale), (16, 12 + index * line_height))
    return GlasshouseWorkbenchRenderResult(workbench.phase, len(lines))


def _render_workbench(
    surface: pygame.Surface,
    font: BitmapFont,
    workbench: GlasshouseWorkbench,
    scale: int,
    palette: GlasshouseWorkbenchPalette,
    compact_sidebar: bool,
) -> GlasshouseWorkbenchRenderResult:
    width, height = surface.get_size()
    line_height = font.measure("M", scale)[1]
    sidebar_width = max(140, width // 4)
    output_height = max(line_height * 4, height // 4)
    source_rect = pygame.Rect(
        sidebar_width + 8,
        line_height + 12,
        width - sidebar_width - 16,
        height - output_height - line_height - 20,
    )
    output_rect = pygame.Rect(8, height - output_height - 8, width - 16, output_height)
    pygame.draw.rect(
        surface, palette.panel, (8, 8, sidebar_width - 12, height - output_height - 20)
    )
    pygame.draw.rect(
        surface, palette.border, (8, 8, sidebar_width - 12, height - output_height - 20), width=1
    )
    pygame.draw.rect(surface, palette.panel, source_rect)
    pygame.draw.rect(surface, palette.border, source_rect, width=1)
    pygame.draw.rect(surface, palette.panel, output_rect)
    pygame.draw.rect(surface, palette.border, output_rect, width=1)
    surface.blit(font.render("POLICIES", palette.heading, scale), (16, 16))
    for index, policy in enumerate(workbench.policies):
        selected = index == workbench.selected_policy_index
        prefix = "> " if selected else "  "
        label = policy.callsign if compact_sidebar else policy.label
        surface.blit(
            font.render(prefix + label, palette.selected if selected else palette.normal, scale),
            (16, 16 + (index + 1) * line_height),
        )
    surface.blit(
        font.render(workbench.selected_policy.label.upper(), palette.heading, scale),
        (sidebar_width + 8, 16),
    )
    previous_clip = surface.get_clip()
    surface.set_clip(source_rect.inflate(-8, -8))
    first_visible_line = workbench.editor.scroll.line
    render_source(
        surface,
        font,
        _source_from_line(workbench.source, first_visible_line),
        (source_rect.x + 4, source_rect.y + 4),
        scale=scale,
    )
    _draw_editor_selection(
        surface,
        font,
        workbench.source,
        workbench.editor.selection.start,
        workbench.editor.selection.end,
        (source_rect.x + 4, source_rect.y + 4),
        line_height,
        scale,
        palette.focus,
        first_visible_line,
    )
    if workbench.compile_output is not None and workbench.compile_output.diagnostics is not None:
        render_inline_diagnostics(
            surface,
            font,
            workbench.source,
            workbench.compile_output.diagnostics,
            (source_rect.x + 4, source_rect.y + 4),
            scale=scale,
            first_visible_line=first_visible_line,
        )
    surface.set_clip(previous_clip)
    if workbench.compile_output is None:
        output_lines = ("COMPILE", "Cmd/Ctrl+Enter: compile selected policy")
        for index, line in enumerate(output_lines):
            surface.blit(
                font.render(line, palette.heading if index == 0 else palette.muted, scale),
                (output_rect.x + 4, output_rect.y + 4 + index * line_height),
            )
        line_count = len(workbench.policies) + len(output_lines) + 2
    else:
        rendered = render_compile_output_panel(
            surface,
            font,
            workbench.compile_output,
            (output_rect.x + 4, output_rect.y + 4),
            scale=scale,
        )
        diagnostic_count = 0
        if workbench.compile_output.diagnostics is not None:
            diagnostics = render_diagnostic_panel(
                surface,
                font,
                workbench.compile_output.diagnostics,
                (output_rect.x + 4, output_rect.y + 4 + rendered.height),
                scale=scale,
            )
            diagnostic_count = diagnostics.entry_count
        line_count = len(workbench.policies) + rendered.line_count + diagnostic_count + 2
    return GlasshouseWorkbenchRenderResult(workbench.phase, line_count)


def _draw_editor_selection(
    surface: pygame.Surface,
    font: BitmapFont,
    source: SourceFile,
    start_offset: int,
    end_offset: int,
    origin: tuple[int, int],
    line_height: int,
    scale: int,
    color: tuple[int, int, int],
    first_visible_line: int,
) -> None:
    if start_offset == end_offset:
        return
    span = source.span(
        ByteOffset(len(source.text[:start_offset].encode("utf-8"))),
        ByteOffset(len(source.text[:end_offset].encode("utf-8"))),
    )
    start, end = source.positions_of(span)
    lines = source.text.split("\n")
    for line_number in range(start.line, end.line + 1):
        if line_number < first_visible_line:
            continue
        line = lines[line_number - 1].removesuffix("\r")
        first_column = start.column if line_number == start.line else 1
        last_column = end.column if line_number == end.line else len(line) + 1
        if first_column == last_column:
            continue
        x = origin[0] + font.measure(line[: first_column - 1].expandtabs(4), scale)[0]
        width = font.measure(line[first_column - 1 : last_column - 1].expandtabs(4), scale)[0]
        minimum_width = font.measure("M", scale)[0]
        y = origin[1] + (line_number - first_visible_line + 1) * line_height - 1
        pygame.draw.line(surface, color, (x, y), (x + max(width, minimum_width) - 1, y))


def _source_from_line(source: SourceFile, first_line: int) -> SourceFile:
    """Return a presentation-only source tail for the editor's selected scroll row."""
    if not isinstance(first_line, int) or isinstance(first_line, bool) or first_line < 1:
        raise ValueError("Glasshouse source view line must be positive")
    lines = source.text.splitlines(keepends=True)
    if first_line > len(lines):
        raise ValueError("Glasshouse source view line exceeds source length")
    return SourceFile(source.file_id, "".join(lines[first_line - 1 :]))
