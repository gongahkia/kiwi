"""Read-only Terminal mission HUD values derived outside the renderer."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.sim.events import CanonicalEvent, EventKind, canonical_event_order, event_kind
from kiwi.sim.objectives import ObjectiveStatus
from kiwi.sim.snapshot import PresentationSnapshot


@dataclass(frozen=True, slots=True)
class TerminalSignalStatus:
    """One queued or recorded signal represented without a command reference."""

    name: str
    target_entity_id: int | None
    queued: bool

    def __post_init__(self) -> None:
        if not isinstance(self.name, str) or not self.name:
            raise ValueError("Terminal signal status name must be text")
        if self.target_entity_id is not None and (
            not isinstance(self.target_entity_id, int)
            or isinstance(self.target_entity_id, bool)
            or self.target_entity_id <= 0
        ):
            raise ValueError("Terminal signal status target must be a positive ID or absent")
        if not isinstance(self.queued, bool):
            raise TypeError("Terminal signal status queue flag must be boolean")

    @property
    def panel_line(self) -> str:
        """Return a concise read-only signal row for the mission HUD."""
        target = "squad" if self.target_entity_id is None else f"operative {self.target_entity_id}"
        prefix = "QUEUED" if self.queued else "LAST SIGNAL"
        return f"{prefix}: {self.name} / {target}"


class TerminalSoundCueKind(StrEnum):
    """The bounded presentation-only Terminal sound vocabulary."""

    FIRE = "fire"
    IMPACT = "impact"
    INJURY = "injury"
    OBJECTIVE_RETRIEVED = "objective_retrieved"
    OBJECTIVE_EXTRACTED = "objective_extracted"
    LOCKDOWN = "lockdown"


@dataclass(frozen=True, slots=True)
class TerminalSoundCue:
    """One event-identified audio request copied from an authority event."""

    event_id: int
    kind: TerminalSoundCueKind

    def __post_init__(self) -> None:
        if (
            not isinstance(self.event_id, int)
            or isinstance(self.event_id, bool)
            or self.event_id <= 0
        ):
            raise ValueError("Terminal sound cue event ID must be positive")
        if not isinstance(self.kind, TerminalSoundCueKind):
            raise TypeError("Terminal sound cue kind is invalid")


def build_terminal_sound_cues(
    events: tuple[CanonicalEvent, ...],
) -> tuple[TerminalSoundCue, ...]:
    """Copy the audible subset of one canonically ordered authority event tuple."""
    if not isinstance(events, tuple):
        raise TypeError("Terminal sound cues require immutable canonical events")
    if canonical_event_order(events) != events:
        raise ValueError("Terminal sound cues require canonical event order")
    cues: list[TerminalSoundCue] = []
    for event in events:
        kind = _sound_cue_kind(event_kind(event))
        if kind is not None:
            cues.append(TerminalSoundCue(event.header.event_id.value, kind))
    return tuple(cues)


def _sound_cue_kind(event: EventKind) -> TerminalSoundCueKind | None:
    if event is EventKind.FIRE_FIRED:
        return TerminalSoundCueKind.FIRE
    if event is EventKind.PROJECTILE_IMPACTED:
        return TerminalSoundCueKind.IMPACT
    if event is EventKind.INJURY_CHANGED:
        return TerminalSoundCueKind.INJURY
    if event is EventKind.OBJECTIVE_RETRIEVED:
        return TerminalSoundCueKind.OBJECTIVE_RETRIEVED
    if event is EventKind.OBJECTIVE_EXTRACTED:
        return TerminalSoundCueKind.OBJECTIVE_EXTRACTED
    if event is EventKind.LOCKDOWN_ACTIVATED:
        return TerminalSoundCueKind.LOCKDOWN
    return None


class TerminalMissionOutcome(StrEnum):
    """The read-only Terminal outcome projected from objective and lockdown state."""

    IN_PROGRESS = "in_progress"
    SUCCESS = "success"
    FAILURE = "failure"


@dataclass(frozen=True, slots=True)
class TerminalMissionSummary:
    """One concise mission status with no authority-state reference."""

    outcome: TerminalMissionOutcome
    objective_status: ObjectiveStatus
    lockdown_active: bool

    def __post_init__(self) -> None:
        if not isinstance(self.outcome, TerminalMissionOutcome):
            raise TypeError("Terminal mission summary outcome is invalid")
        if not isinstance(self.objective_status, ObjectiveStatus):
            raise TypeError("Terminal mission summary objective status is invalid")
        if not isinstance(self.lockdown_active, bool):
            raise TypeError("Terminal mission summary lockdown state must be boolean")

    @property
    def panel_line(self) -> str:
        """Return the terminal or current mission result for the mission HUD."""
        if self.outcome is TerminalMissionOutcome.SUCCESS:
            return "MISSION: SUCCESS / objective extracted"
        if self.outcome is TerminalMissionOutcome.FAILURE:
            return "MISSION: FAILURE / lockdown blocked extraction"
        return f"MISSION: IN PROGRESS / objective {self.objective_status.value}"


def build_terminal_mission_summary(
    objective_status: ObjectiveStatus, *, lockdown_active: bool
) -> TerminalMissionSummary:
    """Project the existing Terminal objective and lockdown facts into a HUD summary."""
    if not isinstance(objective_status, ObjectiveStatus):
        raise TypeError("Terminal mission summary requires an objective status")
    if not isinstance(lockdown_active, bool):
        raise TypeError("Terminal mission summary lockdown state must be boolean")
    if objective_status is ObjectiveStatus.EXTRACTED:
        outcome = TerminalMissionOutcome.SUCCESS
    elif lockdown_active:
        outcome = TerminalMissionOutcome.FAILURE
    else:
        outcome = TerminalMissionOutcome.IN_PROGRESS
    return TerminalMissionSummary(outcome, objective_status, lockdown_active)


@dataclass(frozen=True, slots=True)
class TerminalMissionPresentation:
    """One complete renderer input containing no authoritative mission-state reference."""

    snapshot: PresentationSnapshot
    summary: TerminalMissionSummary
    remaining_lockdown_ticks: int
    signal_status: TerminalSignalStatus | None
    sound_cues: tuple[TerminalSoundCue, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.snapshot, PresentationSnapshot):
            raise TypeError("Terminal mission presentation requires a snapshot")
        if not isinstance(self.summary, TerminalMissionSummary):
            raise TypeError("Terminal mission presentation summary is invalid")
        if (
            not isinstance(self.remaining_lockdown_ticks, int)
            or isinstance(self.remaining_lockdown_ticks, bool)
            or self.remaining_lockdown_ticks < 0
        ):
            raise ValueError("Terminal mission presentation lockdown ticks are invalid")
        if self.signal_status is not None and not isinstance(
            self.signal_status, TerminalSignalStatus
        ):
            raise TypeError("Terminal mission presentation signal status is invalid")
        if not isinstance(self.sound_cues, tuple) or any(
            not isinstance(cue, TerminalSoundCue) for cue in self.sound_cues
        ):
            raise TypeError("Terminal mission presentation sound cues are invalid")
        cue_ids = tuple(cue.event_id for cue in self.sound_cues)
        if cue_ids != tuple(sorted(cue_ids)) or len(set(cue_ids)) != len(cue_ids):
            raise ValueError("Terminal mission presentation sound cues must be event-ID ordered")

    @property
    def panel_lines(self) -> tuple[str, str, str, str, str]:
        """Return fixed-order mission HUD content from copied presentation data."""
        return (
            "TERMINAL",
            self.summary.panel_line,
            f"PHASE: {self.snapshot.phase}  TICK: {self.snapshot.tick}",
            f"LOCKDOWN: T-{self.remaining_lockdown_ticks} ticks",
            "SIGNALS: advance / hold"
            if self.signal_status is None
            else self.signal_status.panel_line,
        )
