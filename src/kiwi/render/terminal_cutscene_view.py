"""Bitmap rendering for bounded non-authoritative Terminal cutscenes."""

from __future__ import annotations

import pygame

from kiwi.render.atlas import TextureAtlas
from kiwi.render.bitmap_font import BitmapFont
from kiwi.ui.terminal_cutscenes import TerminalCutscene, TerminalCutsceneBeatKind


def render_terminal_cutscene(
    surface: pygame.Surface,
    font: BitmapFont,
    cutscene: TerminalCutscene,
    elapsed_milliseconds: int,
    *,
    background: tuple[int, int, int],
    panel: tuple[int, int, int],
    border: tuple[int, int, int],
    heading: tuple[int, int, int],
    normal: tuple[int, int, int],
    atlas: TextureAtlas | None = None,
) -> None:
    """Render one time-indexed scene from immutable content data only."""
    if not isinstance(surface, pygame.Surface):
        raise TypeError("Terminal cutscene requires a pygame surface")
    if not isinstance(font, BitmapFont):
        raise TypeError("Terminal cutscene requires a bitmap font")
    if not isinstance(cutscene, TerminalCutscene):
        raise TypeError("Terminal cutscene is invalid")
    surface.fill(background)
    width, height = surface.get_size()
    pygame.draw.rect(surface, panel, (8, 8, width - 16, height - 16))
    pygame.draw.rect(surface, border, (8, 8, width - 16, height - 16), width=1)
    surface.blit(font.render(cutscene.title.upper(), heading), (20, 20))
    beats = cutscene.visible_beats(elapsed_milliseconds)
    lines = tuple(beat.value for beat in beats if beat.kind is TerminalCutsceneBeatKind.TERMINAL_TEXT)
    sprite = next((beat.value for beat in beats if beat.kind is TerminalCutsceneBeatKind.SPRITE), None)
    if atlas is not None and sprite is not None:
        frame = "operator" if sprite == "operator_seated" else "operative_alert"
        surface.blit(atlas.frame(frame, 120, heading), (width // 2 - 60, 88))
    else:
        pygame.draw.rect(surface, border, (width // 2 - 36, 96, 72, 96), width=1)
        pygame.draw.line(surface, heading, (width // 2, 108), (width // 2, 172), width=2)
    line_height = font.measure("M")[1]
    for index, line in enumerate(lines):
        surface.blit(font.render(line, normal), (28, height - 84 + index * line_height))
    surface.blit(font.render("Enter skips / continues", heading), (28, height - 28))
