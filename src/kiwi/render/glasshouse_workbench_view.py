"""Bitmap rendering for the non-authoritative Glasshouse briefing and workbench."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.render.bitmap_font import BitmapFont
from kiwi.render.compile_output_view import render_compile_output_panel
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
    muted: tuple[int, int, int] = (192, 201, 191)

    def __post_init__(self) -> None:
        for color in (
            self.background,
            self.panel,
            self.border,
            self.heading,
            self.normal,
            self.selected,
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
    surface.fill(palette.background)
    if workbench.phase is GlasshouseFlowPhase.BRIEFING:
        return _render_briefing(surface, font, workbench, scale, palette)
    return _render_workbench(surface, font, workbench, scale, palette)


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
        surface.blit(
            font.render(
                prefix + policy.label, palette.selected if selected else palette.normal, scale
            ),
            (16, 16 + (index + 1) * line_height),
        )
    surface.blit(
        font.render(workbench.selected_policy.label.upper(), palette.heading, scale),
        (sidebar_width + 8, 16),
    )
    previous_clip = surface.get_clip()
    surface.set_clip(source_rect.inflate(-8, -8))
    render_source(
        surface,
        font,
        workbench.source,
        (source_rect.x + 4, source_rect.y + 4),
        scale=scale,
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
        line_count = len(workbench.policies) + rendered.line_count + 2
    return GlasshouseWorkbenchRenderResult(workbench.phase, line_count)
