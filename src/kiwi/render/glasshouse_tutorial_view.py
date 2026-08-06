"""Bitmap rendering for the read-only Glasshouse language guide."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.render.bitmap_font import BitmapFont
from kiwi.ui.glasshouse_tutorial import GlasshouseTutorial


def _validate_color(color: tuple[int, int, int]) -> None:
    if not isinstance(color, tuple) or len(color) != 3:
        raise ValueError("Glasshouse tutorial palette color must be an RGB tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in color):
        raise ValueError("Glasshouse tutorial palette color components must be integers")
    if any(component < 0 or component > 255 for component in color):
        raise ValueError("Glasshouse tutorial palette color components must be 0 through 255")


@dataclass(frozen=True, slots=True)
class GlasshouseTutorialPalette:
    """Fixed readable colours for the single-construct language guide."""

    background: tuple[int, int, int] = (10, 14, 19)
    heading: tuple[int, int, int] = (111, 216, 238)
    code: tuple[int, int, int] = (111, 216, 168)
    normal: tuple[int, int, int] = (206, 221, 231)
    prompt: tuple[int, int, int] = (245, 189, 74)

    def __post_init__(self) -> None:
        for color in (self.background, self.heading, self.code, self.normal, self.prompt):
            _validate_color(color)


DEFAULT_GLASSHOUSE_TUTORIAL_PALETTE = GlasshouseTutorialPalette()


@dataclass(frozen=True, slots=True)
class GlasshouseTutorialRenderResult:
    """The selected lesson index and rendered row count for one guide frame."""

    selected_lesson_index: int
    line_count: int

    def __post_init__(self) -> None:
        if (
            not isinstance(self.selected_lesson_index, int)
            or isinstance(self.selected_lesson_index, bool)
            or self.selected_lesson_index < 0
        ):
            raise ValueError("Glasshouse tutorial render selection is invalid")
        if not isinstance(self.line_count, int) or isinstance(self.line_count, bool):
            raise TypeError("Glasshouse tutorial render line count must be an integer")
        if self.line_count <= 0:
            raise ValueError("Glasshouse tutorial render line count must be positive")


def render_glasshouse_tutorial(
    surface: pygame.Surface,
    font: BitmapFont,
    tutorial: GlasshouseTutorial,
    *,
    scale: int = 1,
    palette: GlasshouseTutorialPalette = DEFAULT_GLASSHOUSE_TUTORIAL_PALETTE,
) -> GlasshouseTutorialRenderResult:
    """Render one immutable lesson without reading source or authority state."""
    if not isinstance(surface, pygame.Surface):
        raise TypeError("Glasshouse tutorial rendering requires a pygame surface")
    if not isinstance(font, BitmapFont):
        raise TypeError("Glasshouse tutorial rendering requires a bitmap font")
    if not isinstance(tutorial, GlasshouseTutorial):
        raise TypeError("Glasshouse tutorial rendering requires tutorial state")
    if not isinstance(scale, int) or isinstance(scale, bool) or scale < 1:
        raise ValueError("Glasshouse tutorial render scale must be positive")
    if not isinstance(palette, GlasshouseTutorialPalette):
        raise TypeError("Glasshouse tutorial palette is invalid")
    lesson = tutorial.selected_lesson
    lines = (
        ("GLASSHOUSE LANGUAGE GUIDE", palette.heading),
        (f"LESSON {tutorial.selected_lesson_index + 1}/{len(tutorial.lessons)}", palette.normal),
        (lesson.title, palette.heading),
        *((line, palette.code) for line in lesson.code_lines),
        *((line, palette.normal) for line in lesson.explanation_lines),
        (f"TRY: {lesson.try_line}", palette.prompt),
        ("PREVIOUS / NEXT: change lesson only", palette.normal),
    )
    surface.fill(palette.background)
    line_height = font.measure("M", scale)[1]
    for index, (line, color) in enumerate(lines):
        surface.blit(font.render(line, color, scale), (16, 12 + index * line_height))
    return GlasshouseTutorialRenderResult(tutorial.selected_lesson_index, len(lines))
