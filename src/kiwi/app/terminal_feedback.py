"""Provenance-safe forecast and consequence-receipt projections for practice levels."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.app.terminal_levels import TerminalPracticeLevel
from kiwi.trace.model import (
    CausalTrace,
    ConsequenceTrace,
    IntentionResolutionTrace,
    IntentionTrace,
    WorldEventTrace,
)


class TerminalFeedbackCertainty(StrEnum):
    """How the UI may truthfully describe one piece of player-facing evidence."""

    KNOWN = "known"
    INFERRED = "inferred"
    UNKNOWN = "unknown"


@dataclass(frozen=True, slots=True)
class TerminalFeedbackLine:
    """One bounded, renderer-ready statement with an explicit information boundary."""

    certainty: TerminalFeedbackCertainty
    label: str
    summary: str

    def __post_init__(self) -> None:
        if not isinstance(self.certainty, TerminalFeedbackCertainty):
            raise TypeError("Terminal feedback certainty is invalid")
        if not isinstance(self.label, str) or not self.label:
            raise ValueError("Terminal feedback label must be text")
        if not isinstance(self.summary, str) or not self.summary:
            raise ValueError("Terminal feedback summary must be text")


@dataclass(frozen=True, slots=True)
class TerminalForecast:
    """A non-omniscient preview of authored intelligence and player policy output."""

    lines: tuple[TerminalFeedbackLine, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.lines, tuple) or not self.lines:
            raise ValueError("Terminal forecast needs immutable feedback lines")
        if any(not isinstance(line, TerminalFeedbackLine) for line in self.lines):
            raise TypeError("Terminal forecast lines are invalid")


@dataclass(frozen=True, slots=True)
class TerminalCausalReceipt:
    """A compact trace-backed account of one player policy consequence."""

    lines: tuple[TerminalFeedbackLine, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.lines, tuple) or not self.lines:
            raise ValueError("Terminal causal receipt needs immutable feedback lines")
        if any(not isinstance(line, TerminalFeedbackLine) for line in self.lines):
            raise TypeError("Terminal causal receipt lines are invalid")


def terminal_forecast(level: TerminalPracticeLevel, trace: CausalTrace) -> TerminalForecast:
    """Project only authored intelligence and the recorded player intention."""
    if not isinstance(level, TerminalPracticeLevel):
        raise TypeError("Terminal forecast level is invalid")
    if not isinstance(trace, CausalTrace):
        raise TypeError("Terminal forecast trace is invalid")
    intention = next(
        (record for record in trace.records if isinstance(record, IntentionTrace)), None
    )
    intent_summary = (
        f"daemon emits {intention.origin.kind.value} at t{intention.tick}"
        if intention is not None
        else "current source emits no retained intention"
    )
    return TerminalForecast(
        tuple(
            TerminalFeedbackLine(TerminalFeedbackCertainty.KNOWN, "known", threat)
            for threat in level.known_threats[:2]
        )
        + (
            TerminalFeedbackLine(
                TerminalFeedbackCertainty.INFERRED,
                "your daemon",
                intent_summary,
            ),
            TerminalFeedbackLine(
                TerminalFeedbackCertainty.UNKNOWN,
                "boundary",
                "unobserved hostile state is intentionally not forecast",
            ),
        )
    )


def terminal_causal_receipt(trace: CausalTrace) -> TerminalCausalReceipt:
    """Return source-to-world evidence in retained causal-record order."""
    if not isinstance(trace, CausalTrace):
        raise TypeError("Terminal causal receipt trace is invalid")
    intention = next(
        (record for record in trace.records if isinstance(record, IntentionTrace)), None
    )
    resolution = next(
        (record for record in trace.records if isinstance(record, IntentionResolutionTrace)), None
    )
    world_event = next(
        (
            record
            for record in trace.records
            if isinstance(record, WorldEventTrace)
            and resolution is not None
            and record.event_id in resolution.world_event_ids
        ),
        None,
    )
    consequence = next(
        (record for record in trace.records if isinstance(record, ConsequenceTrace)), None
    )
    return TerminalCausalReceipt(
        (
            TerminalFeedbackLine(
                TerminalFeedbackCertainty.INFERRED,
                "source",
                "selected policy expression" if intention is not None else "no intention emitted",
            ),
            TerminalFeedbackLine(
                TerminalFeedbackCertainty.INFERRED,
                "intention",
                intention.origin.kind.value if intention is not None else "none",
            ),
            TerminalFeedbackLine(
                TerminalFeedbackCertainty.KNOWN,
                "resolution",
                (
                    resolution.status.value
                    if resolution is not None
                    else "no retained intention resolution"
                ),
            ),
            TerminalFeedbackLine(
                TerminalFeedbackCertainty.KNOWN,
                "outcome",
                (
                    consequence.summary
                    if consequence is not None
                    else world_event.summary
                    if world_event is not None
                    else "no major consequence retained"
                ),
            ),
        )
    )
