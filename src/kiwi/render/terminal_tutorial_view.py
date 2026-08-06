"""Bitmap rendering for the read-only Terminal language guide."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.render.bitmap_font import BitmapFont
from kiwi.ui.terminal_tutorial import TerminalTutorial


def _validate_color(color: tuple[int, int, int]) -> None:
    if not isinstance(color, tuple) or len(color) != 3:
        raise ValueError("Terminal tutorial palette color must be an RGB tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in color):
        raise ValueError("Terminal tutorial palette color components must be integers")
    if any(component < 0 or component > 255 for component in color):
        raise ValueError("Terminal tutorial palette color components must be 0 through 255")


@dataclass(frozen=True, slots=True)
class TerminalTutorialPalette:
    """Fixed readable colours for the single-construct language guide."""

    background: tuple[int, int, int] = (10, 14, 19)
    heading: tuple[int, int, int] = (111, 216, 238)
    code: tuple[int, int, int] = (111, 216, 168)
    normal: tuple[int, int, int] = (206, 221, 231)
    prompt: tuple[int, int, int] = (245, 189, 74)

    def __post_init__(self) -> None:
        for color in (self.background, self.heading, self.code, self.normal, self.prompt):
            _validate_color(color)


DEFAULT_TERMINAL_TUTORIAL_PALETTE = TerminalTutorialPalette()


@dataclass(frozen=True, slots=True)
class TerminalTutorialRenderResult:
    """The selected lesson index and rendered row count for one guide frame."""

    selected_lesson_index: int
    line_count: int

    def __post_init__(self) -> None:
        if (
            not isinstance(self.selected_lesson_index, int)
            or isinstance(self.selected_lesson_index, bool)
            or self.selected_lesson_index < 0
        ):
            raise ValueError("Terminal tutorial render selection is invalid")
        if not isinstance(self.line_count, int) or isinstance(self.line_count, bool):
            raise TypeError("Terminal tutorial render line count must be an integer")
        if self.line_count <= 0:
            raise ValueError("Terminal tutorial render line count must be positive")


def render_terminal_tutorial(
    surface: pygame.Surface,
    font: BitmapFont,
    tutorial: TerminalTutorial,
    *,
    scale: int = 1,
    palette: TerminalTutorialPalette = DEFAULT_TERMINAL_TUTORIAL_PALETTE,
) -> TerminalTutorialRenderResult:
    """Render one immutable lesson without reading source or authority state."""
    if not isinstance(surface, pygame.Surface):
        raise TypeError("Terminal tutorial rendering requires a pygame surface")
    if not isinstance(font, BitmapFont):
        raise TypeError("Terminal tutorial rendering requires a bitmap font")
    if not isinstance(tutorial, TerminalTutorial):
        raise TypeError("Terminal tutorial rendering requires tutorial state")
    if not isinstance(scale, int) or isinstance(scale, bool) or scale < 1:
        raise ValueError("Terminal tutorial render scale must be positive")
    if not isinstance(palette, TerminalTutorialPalette):
        raise TypeError("Terminal tutorial palette is invalid")
    lesson = tutorial.selected_lesson
    lines = (
        ("TERMINAL LANGUAGE GUIDE", palette.heading),
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
    return TerminalTutorialRenderResult(tutorial.selected_lesson_index, len(lines))
