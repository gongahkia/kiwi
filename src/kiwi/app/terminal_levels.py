"""Authored, presentation-facing practice-level metadata for KIWI // Terminal."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class TerminalLevelId(StrEnum):
    """Stable IDs for the shipped local practice sequence."""

    FIRST_LINK = "first_link"
    TERMINAL = "terminal"
    GLASSHOUSE = "glasshouse"
    REDLINE = "redline"


class TerminalPracticeSignal(StrEnum):
    """The deliberately small strategic vocabulary surfaced by practice levels."""

    ADVANCE = "advance"
    HOLD = "hold"


@dataclass(frozen=True, slots=True)
class TerminalPracticeLevel:
    """One finite practice brief, intro, and player-facing programming objective."""

    level_id: TerminalLevelId
    title: str
    objective: str
    time_pressure: str
    known_threats: tuple[str, ...]
    try_prompt: str
    intro_cutscene_id: str
    onboarding: bool = False
    permitted_signals: tuple[TerminalPracticeSignal, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.level_id, TerminalLevelId):
            raise TypeError("Terminal practice level ID is invalid")
        text = (
            self.title,
            self.objective,
            self.time_pressure,
            self.try_prompt,
            self.intro_cutscene_id,
        )
        if any(not isinstance(value, str) or not value for value in text):
            raise ValueError("Terminal practice level text must be non-empty")
        if not isinstance(self.known_threats, tuple) or not self.known_threats:
            raise ValueError("Terminal practice level needs known threat text")
        if any(not isinstance(value, str) or not value for value in self.known_threats):
            raise ValueError("Terminal practice threats must be text")
        if not isinstance(self.onboarding, bool):
            raise TypeError("Terminal practice onboarding flag must be boolean")
        if not isinstance(self.permitted_signals, tuple):
            raise TypeError("Terminal practice signals must be immutable")
        if any(not isinstance(signal, TerminalPracticeSignal) for signal in self.permitted_signals):
            raise TypeError("Terminal practice signals are invalid")
        if len(set(self.permitted_signals)) != len(self.permitted_signals):
            raise ValueError("Terminal practice signals must be unique")


TERMINAL_PRACTICE_LEVELS = (
    TerminalPracticeLevel(
        TerminalLevelId.FIRST_LINK,
        "FIRST LINK // SAFE ROUTE",
        "Teach Lark to wait when the contact estimate is still uncertain.",
        "Offline practice: no campaign cost, replayable at any time.",
        (
            "KNOWN: Lark sees one contact with a 0.5m uncertainty radius.",
            "KNOWN: an exposed route triggers one predictable ICE response.",
            "UNKNOWN: no hidden hostile state is shown to the player.",
        ),
        "TRY: change the marked 1m caution threshold to 0m, then watch the route settle.",
        "first_link_intro",
        onboarding=True,
    ),
    TerminalPracticeLevel(
        TerminalLevelId.TERMINAL,
        "TERMINAL // HOSTILE MAINFRAME",
        "Route the daemon bundle to a payload before trace containment closes the route.",
        "Trace containment is fixed at 90 seconds after deployment.",
        (
            "KNOWN: hostile ICE telemetry is incomplete.",
            "KNOWN: Lark starts with one 0.5m-uncertainty contact.",
            "UNKNOWN: the hostile response beyond observed evidence stays hidden.",
        ),
        "TRY: inspect the selected route decision, then test a smaller caution threshold.",
        "terminal_intro",
    ),
    TerminalPracticeLevel(
        TerminalLevelId.GLASSHOUSE,
        "GLASSHOUSE // COVER ROUTE",
        "Use Option matching to make an observed route choice explicit, then inspect arbitration.",
        "No hidden deadline: solve the readable cover-routing puzzle first.",
        (
            "KNOWN: the visible route contains one high-cover alternative.",
            "KNOWN: only observed contacts can influence the daemon branch.",
            "UNKNOWN: unobserved ICE remains outside the forecast.",
        ),
        "TRY: follow the match branch and compare the emitted route intention with the receipt.",
        "glasshouse_intro",
    ),
    TerminalPracticeLevel(
        TerminalLevelId.REDLINE,
        "REDLINE // EXTRACTION WINDOW",
        "Balance a short extraction window against a safe Hold-versus-Advance policy choice.",
        "The visible trace clock makes pressure explicit; it never changes a policy silently.",
        (
            "KNOWN: the extraction window is limited and the current route is exposed.",
            "KNOWN: Advance is a typed policy input; Hold sends no advance signal.",
            "UNKNOWN: the forecast does not reveal unobserved hostile choices.",
        ),
        "TRY: send Advance or Hold, then inspect the consequence receipt.",
        "redline_intro",
        permitted_signals=(TerminalPracticeSignal.ADVANCE, TerminalPracticeSignal.HOLD),
    ),
)


def terminal_practice_level(level_id: TerminalLevelId) -> TerminalPracticeLevel:
    """Return one level in explicit catalog order."""
    if not isinstance(level_id, TerminalLevelId):
        raise TypeError("Terminal practice level ID is invalid")
    for level in TERMINAL_PRACTICE_LEVELS:
        if level.level_id is level_id:
            return level
    raise AssertionError("Terminal practice level catalog is incomplete")
