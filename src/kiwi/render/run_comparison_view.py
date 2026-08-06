"""Bitmap rendering for immutable compatible-run comparison projections."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.render.bitmap_font import BitmapFont
from kiwi.replay.comparison import PolicyExecutionComparison, RunDifferenceKind
from kiwi.ui.run_comparison import RunComparisonView


def _validate_color(color: tuple[int, int, int]) -> None:
    if not isinstance(color, tuple) or len(color) != 3:
        raise ValueError("run comparison palette color must be a three-item tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in color):
        raise ValueError("run comparison palette color components must be integers")
    if any(component < 0 or component > 255 for component in color):
        raise ValueError("run comparison palette color components must be 0 through 255")


def _validate_origin(origin: tuple[int, int]) -> None:
    if not isinstance(origin, tuple) or len(origin) != 2:
        raise TypeError("run comparison rendering origin must be a two-item tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in origin):
        raise TypeError("run comparison rendering origin components must be integers")


@dataclass(frozen=True, slots=True)
class RunComparisonPalette:
    heading: tuple[int, int, int] = (110, 177, 223)
    normal: tuple[int, int, int] = (206, 221, 231)
    changed: tuple[int, int, int] = (245, 189, 74)
    incompatible: tuple[int, int, int] = (239, 99, 99)

    def __post_init__(self) -> None:
        _validate_color(self.heading)
        _validate_color(self.normal)
        _validate_color(self.changed)
        _validate_color(self.incompatible)


DEFAULT_RUN_COMPARISON_PALETTE = RunComparisonPalette()


@dataclass(frozen=True, slots=True)
class RunComparisonRenderResult:
    line_count: int
    height: int


def render_run_comparison_view(
    surface: pygame.Surface,
    font: BitmapFont,
    comparison: RunComparisonView,
    origin: tuple[int, int],
    *,
    scale: int = 1,
    palette: RunComparisonPalette = DEFAULT_RUN_COMPARISON_PALETTE,
) -> RunComparisonRenderResult:
    """Render compatibility-gated replay comparison summaries onto an existing surface."""
    if not isinstance(surface, pygame.Surface) or not isinstance(font, BitmapFont):
        raise TypeError("run comparison rendering requires a pygame surface and bitmap font")
    if not isinstance(comparison, RunComparisonView):
        raise TypeError("run comparison rendering requires a run comparison view")
    _validate_origin(origin)
    if not isinstance(scale, int) or isinstance(scale, bool) or scale < 1:
        raise ValueError("run comparison rendering scale must be positive")
    if not isinstance(palette, RunComparisonPalette):
        raise TypeError("run comparison rendering requires a run comparison palette")
    lines = _lines(comparison, palette)
    line_height = font.measure("M", scale)[1]
    for index, (text, color) in enumerate(lines):
        surface.blit(font.render(text, color, scale), (origin[0], origin[1] + index * line_height))
    return RunComparisonRenderResult(len(lines), len(lines) * line_height)


def _lines(
    comparison: RunComparisonView,
    palette: RunComparisonPalette,
) -> tuple[tuple[str, tuple[int, int, int]], ...]:
    if not comparison.compatibility.is_compatible:
        return (
            ("comparison: incompatible baseline", palette.incompatible),
            *(
                (f"{failure.code}: {failure.message}", palette.incompatible)
                for failure in comparison.compatibility.failures
            ),
        )
    if comparison.policy_execution is None or comparison.consequences is None:
        raise AssertionError("compatible run comparison has incomplete projections")
    lines: list[tuple[str, tuple[int, int, int]]] = [("comparison: compatible", palette.heading)]
    lines.extend(
        (
            f"policy e{difference.entity_id.value}: {difference.kind.value}",
            palette.changed,
        )
        for difference in comparison.compatibility.policy_differences
    )
    lines.append(_policy_line(comparison.policy_execution, palette))
    lines.append(_intention_line(comparison.policy_execution, palette))
    lines.append(_state_line(comparison, palette))
    if comparison.consequences.matches:
        lines.append(("consequences: match", palette.normal))
    else:
        lines.extend(
            (
                f"consequence t{difference.key.tick} {difference.key.kind.value}: "
                f"{difference.kind.value}",
                palette.changed,
            )
            for difference in comparison.consequences.differences
        )
    return tuple(lines)


def _policy_line(
    comparison: PolicyExecutionComparison,
    palette: RunComparisonPalette,
) -> tuple[str, tuple[int, int, int]]:
    difference = comparison.evaluation_difference
    if difference is None:
        return ("policy evaluation: match", palette.normal)
    return (
        f"policy evaluation t{difference.key.tick} e{difference.key.entity_id.value}: "
        f"{_run_difference_label(difference.kind)}",
        palette.changed,
    )


def _intention_line(
    comparison: PolicyExecutionComparison,
    palette: RunComparisonPalette,
) -> tuple[str, tuple[int, int, int]]:
    difference = comparison.intention_difference
    if difference is None:
        return ("intention: match", palette.normal)
    return (
        f"intention t{difference.key.tick} e{difference.key.issuer_entity_id.value} "
        f"#{difference.key.policy_order}: {_run_difference_label(difference.kind)}",
        palette.changed,
    )


def _state_line(
    comparison: RunComparisonView,
    palette: RunComparisonPalette,
) -> tuple[str, tuple[int, int, int]]:
    if comparison.state_divergence is None:
        return ("state: match", palette.normal)
    difference = comparison.state_divergence.difference
    return (
        f"state t{comparison.state_divergence.tick} {difference.path}: "
        f"{difference.expected} -> {difference.actual}",
        palette.changed,
    )


def _run_difference_label(kind: RunDifferenceKind) -> str:
    if kind in (RunDifferenceKind.ADDED, RunDifferenceKind.REMOVED, RunDifferenceKind.CHANGED):
        return kind.value
    raise AssertionError("unsupported run difference kind")
