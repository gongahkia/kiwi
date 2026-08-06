"""Bitmap local-result histogram page for Glasshouse challenge attempts."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.app.challenge_results import ChallengeHistory, ChallengeOutcome, ChallengeResult
from kiwi.render.bitmap_font import BitmapFont


@dataclass(frozen=True, slots=True)
class ChallengeResultsPalette:
    background: tuple[int, int, int]
    panel: tuple[int, int, int]
    border: tuple[int, int, int]
    heading: tuple[int, int, int]
    normal: tuple[int, int, int]
    success: tuple[int, int, int]
    failure: tuple[int, int, int]
    chart: tuple[int, int, int]


def render_challenge_results(
    surface: pygame.Surface,
    font: BitmapFont,
    history: ChallengeHistory,
    current: ChallengeResult,
    palette: ChallengeResultsPalette,
) -> None:
    """Render four explicit optimization metrics plus one local tick histogram."""
    if not isinstance(surface, pygame.Surface):
        raise TypeError("challenge result view requires a pygame surface")
    if not isinstance(font, BitmapFont):
        raise TypeError("challenge result view requires a bitmap font")
    if not isinstance(history, ChallengeHistory) or not isinstance(current, ChallengeResult):
        raise TypeError("challenge result view requires local result data")
    if not isinstance(palette, ChallengeResultsPalette):
        raise TypeError("challenge result view palette is invalid")
    surface.fill(palette.background)
    line_height = font.measure("M")[1]
    _panel(surface, palette, (8, 8, surface.get_width() - 16, line_height * 8 + 10))
    outcome_color = (
        palette.success if current.outcome is ChallengeOutcome.SUCCESS else palette.failure
    )
    lines = (
        "RESULTS / LOCAL OPTIMIZATION",
        f"CHALLENGE {current.challenge_id}",
        f"OUTCOME: {current.outcome.value}  CASUALTIES: {current.casualties}",
        f"TICKS: {current.ticks}  BYTECODE: {current.bytecode_bytes} bytes",
        f"VM INSN: {current.vm_instructions}  POLICY EVALS: {current.policy_evaluations}",
        "NO COMPOSITE SCORE: improve the dimension you care about.",
    )
    for index, line in enumerate(lines):
        color = palette.heading if index == 0 else outcome_color if index == 2 else palette.normal
        surface.blit(font.render(line, color), (14, 14 + index * line_height))
    _render_tick_histogram(surface, font, history, current, palette, 8, line_height * 9 + 18)


def _panel(
    surface: pygame.Surface, palette: ChallengeResultsPalette, rect: tuple[int, int, int, int]
) -> None:
    pygame.draw.rect(surface, palette.panel, rect)
    pygame.draw.rect(surface, palette.border, rect, width=1)


def _render_tick_histogram(
    surface: pygame.Surface,
    font: BitmapFont,
    history: ChallengeHistory,
    current: ChallengeResult,
    palette: ChallengeResultsPalette,
    x: int,
    y: int,
) -> None:
    buckets = history.histogram(current.challenge_id, "ticks")
    line_height = font.measure("M")[1]
    surface.blit(font.render("LOCAL TICK HISTOGRAM", palette.heading), (x, y))
    if not buckets:
        surface.blit(
            font.render("No completed local attempts.", palette.normal), (x, y + line_height)
        )
        return
    chart_y = y + line_height * 2
    chart_height = max(20, surface.get_height() - chart_y - 12)
    width = max(1, (surface.get_width() - x * 2) // len(buckets))
    maximum = max(bucket.count for bucket in buckets)
    for index, bucket in enumerate(buckets):
        height = max(1, bucket.count * chart_height // maximum)
        rect = pygame.Rect(
            x + index * width + 1, chart_y + chart_height - height, width - 3, height
        )
        pygame.draw.rect(surface, palette.chart, rect)
        label = str(bucket.minimum) if bucket.minimum == bucket.maximum else f"{bucket.minimum}+"
        surface.blit(font.render(label, palette.normal), (rect.x, chart_y + chart_height + 2))
