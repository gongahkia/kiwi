"""BigBlue Terminal bitmap text and integer nearest-neighbour scaling."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import pygame

from kiwi.render.pygame_lifecycle import initialise_pygame

BIGBLUETERM_FONT_FILENAME = "BigBlueTerm437NerdFontMono-Regular.ttf"
BIGBLUETERM_FONT_PATH = Path(__file__).with_name("assets") / BIGBLUETERM_FONT_FILENAME
BIGBLUETERM_NATIVE_PIXEL_HEIGHT = 12


class BitmapFontLoadError(RuntimeError):
    """The bundled BigBlue Terminal font could not be loaded."""


@dataclass(frozen=True, slots=True)
class BitmapFont:
    """One loaded pixel font rendered without antialiasing into bitmap surfaces."""

    source_path: Path
    pixel_height: int
    _font: pygame.font.Font

    def __post_init__(self) -> None:
        if not isinstance(self.source_path, Path):
            raise ValueError("bitmap font source path must be a Path")
        if not isinstance(self.pixel_height, int) or isinstance(self.pixel_height, bool):
            raise ValueError("bitmap font pixel height must be an integer")
        if self.pixel_height <= 0:
            raise ValueError("bitmap font pixel height must be positive")
        if not isinstance(self._font, pygame.font.Font):
            raise ValueError("bitmap font requires a pygame font")

    def render(self, text: str, color: tuple[int, int, int], scale: int = 1) -> pygame.Surface:
        """Render unaliased text, then apply an integer nearest-neighbour scale."""
        if not isinstance(text, str):
            raise TypeError("bitmap text must be a string")
        _color(color)
        return scale_nearest_neighbour(self._font.render(text, False, color), scale)

    def measure(self, text: str, scale: int = 1) -> tuple[int, int]:
        """Return unaliased rendered bounds at one positive integer scale."""
        if not isinstance(text, str):
            raise TypeError("bitmap text must be a string")
        if not isinstance(scale, int) or isinstance(scale, bool) or scale <= 0:
            raise ValueError("bitmap text scale must be a positive integer")
        width, height = self._font.size(text)
        return (width * scale, height * scale)


def load_bitmap_font(
    source_path: Path = BIGBLUETERM_FONT_PATH,
    pixel_height: int = BIGBLUETERM_NATIVE_PIXEL_HEIGHT,
) -> BitmapFont:
    """Load BigBlue Terminal at its native 12-pixel height by default."""
    if not isinstance(source_path, Path):
        raise TypeError("bitmap font source path must be a Path")
    if not isinstance(pixel_height, int) or isinstance(pixel_height, bool) or pixel_height <= 0:
        raise ValueError("bitmap font pixel height must be a positive integer")
    initialise_pygame()
    try:
        font = pygame.font.Font(source_path, pixel_height)
    except (OSError, pygame.error) as error:
        raise BitmapFontLoadError(f"could not load bitmap font {source_path}") from error
    return BitmapFont(source_path, pixel_height, font)


def scale_nearest_neighbour(surface: pygame.Surface, scale: int) -> pygame.Surface:
    """Scale a surface by a positive integer with pygame's unfiltered fast scaler."""
    if not isinstance(surface, pygame.Surface):
        raise TypeError("nearest-neighbour scaling requires a pygame surface")
    if not isinstance(scale, int) or isinstance(scale, bool) or scale <= 0:
        raise ValueError("nearest-neighbour scale must be a positive integer")
    return pygame.transform.scale(
        surface,
        (surface.get_width() * scale, surface.get_height() * scale),
    )


def _color(value: tuple[int, int, int]) -> None:
    if not isinstance(value, tuple) or len(value) != 3:
        raise ValueError("bitmap text color must be a three-item tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in value):
        raise ValueError("bitmap text color components must be integers")
    if any(not 0 <= component <= 255 for component in value):
        raise ValueError("bitmap text color components must be 0 through 255")
