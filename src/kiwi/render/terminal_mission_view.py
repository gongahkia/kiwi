"""Bitmap tactical HUD for one non-authoritative Terminal execution view."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.render.bitmap_font import BitmapFont
from kiwi.render.camera import Camera
from kiwi.render.pygame_app import render_tactical_view
from kiwi.render.terminal_audio import TerminalSoundPlayer
from kiwi.ui.terminal_mission import TerminalMissionOutcome, TerminalMissionPresentation


def _validate_color(color: tuple[int, int, int]) -> None:
    if not isinstance(color, tuple) or len(color) != 3:
        raise ValueError("Terminal mission palette color must be an RGB tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in color):
        raise ValueError("Terminal mission palette color components must be integers")
    if any(component < 0 or component > 255 for component in color):
        raise ValueError("Terminal mission palette color components must be 0 through 255")


@dataclass(frozen=True, slots=True)
class TerminalMissionPalette:
    """Fixed mission HUD colours distinct from authority and input state."""

    panel: tuple[int, int, int] = (10, 14, 19)
    border: tuple[int, int, int] = (68, 119, 142)
    heading: tuple[int, int, int] = (111, 216, 238)
    normal: tuple[int, int, int] = (206, 221, 231)
    signal: tuple[int, int, int] = (111, 216, 168)
    warning: tuple[int, int, int] = (245, 189, 74)
    failure: tuple[int, int, int] = (235, 106, 89)

    def __post_init__(self) -> None:
        for color in (
            self.panel,
            self.border,
            self.heading,
            self.normal,
            self.signal,
            self.warning,
            self.failure,
        ):
            _validate_color(color)


DEFAULT_TERMINAL_MISSION_PALETTE = TerminalMissionPalette()


@dataclass(frozen=True, slots=True)
class TerminalMissionRenderResult:
    """The fixed HUD row count for one rendered Terminal mission frame."""

    line_count: int

    def __post_init__(self) -> None:
        if not isinstance(self.line_count, int) or isinstance(self.line_count, bool):
            raise TypeError("Terminal mission render line count must be an integer")
        if self.line_count <= 0:
            raise ValueError("Terminal mission render line count must be positive")


def render_terminal_mission(
    surface: pygame.Surface,
    font: BitmapFont,
    presentation: TerminalMissionPresentation,
    camera: Camera,
    *,
    scale: int = 1,
    palette: TerminalMissionPalette = DEFAULT_TERMINAL_MISSION_PALETTE,
    sound_player: TerminalSoundPlayer | None = None,
) -> TerminalMissionRenderResult:
    """Render copied mission data without accessing authority state or commands."""
    if not isinstance(surface, pygame.Surface):
        raise TypeError("Terminal mission rendering requires a pygame surface")
    if not isinstance(font, BitmapFont):
        raise TypeError("Terminal mission rendering requires a bitmap font")
    if not isinstance(presentation, TerminalMissionPresentation):
        raise TypeError("Terminal mission rendering requires mission presentation")
    if not isinstance(camera, Camera):
        raise TypeError("Terminal mission rendering requires a camera")
    if not isinstance(scale, int) or isinstance(scale, bool) or scale < 1:
        raise ValueError("Terminal mission render scale must be positive")
    if not isinstance(palette, TerminalMissionPalette):
        raise TypeError("Terminal mission render palette is invalid")
    if sound_player is not None and not isinstance(sound_player, TerminalSoundPlayer):
        raise TypeError("Terminal mission sound player is invalid")
    if sound_player is not None:
        sound_player.play(presentation.sound_cues)
    render_tactical_view(
        surface,
        presentation.snapshot,
        camera,
    )
    lines = _status_lines(presentation, palette)
    line_height = font.measure("M", scale)[1]
    panel_height = len(lines) * line_height + 8
    pygame.draw.rect(surface, palette.panel, (4, 4, surface.get_width() - 8, panel_height))
    pygame.draw.rect(
        surface, palette.border, (4, 4, surface.get_width() - 8, panel_height), width=1
    )
    for index, (text, color) in enumerate(lines):
        surface.blit(font.render(text, color, scale), (8, 8 + index * line_height))
    return TerminalMissionRenderResult(len(lines))


def _status_lines(
    presentation: TerminalMissionPresentation,
    palette: TerminalMissionPalette,
) -> tuple[tuple[str, tuple[int, int, int]], ...]:
    lines = presentation.panel_lines
    return (
        (lines[0], palette.heading),
        (
            lines[1],
            palette.signal
            if presentation.summary.outcome is TerminalMissionOutcome.SUCCESS
            else palette.failure
            if presentation.summary.outcome is TerminalMissionOutcome.FAILURE
            else palette.normal,
        ),
        (lines[2], palette.normal),
        (lines[3], palette.warning),
        (lines[4], palette.signal),
    )
