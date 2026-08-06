"""Read-only Glasshouse mission HUD values derived outside the renderer."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.sim.events import CanonicalEvent, EventKind, canonical_event_order, event_kind
from kiwi.sim.objectives import ObjectiveStatus
from kiwi.sim.snapshot import PresentationSnapshot


@dataclass(frozen=True, slots=True)
class GlasshouseSignalStatus:
    """One queued or recorded signal represented without a command reference."""

    name: str
    target_entity_id: int | None
    queued: bool

    def __post_init__(self) -> None:
        if not isinstance(self.name, str) or not self.name:
            raise ValueError("Glasshouse signal status name must be text")
        if self.target_entity_id is not None and (
            not isinstance(self.target_entity_id, int)
            or isinstance(self.target_entity_id, bool)
            or self.target_entity_id <= 0
        ):
            raise ValueError("Glasshouse signal status target must be a positive ID or absent")
        if not isinstance(self.queued, bool):
            raise TypeError("Glasshouse signal status queue flag must be boolean")

    @property
    def panel_line(self) -> str:
        """Return a concise read-only signal row for the mission HUD."""
        target = "squad" if self.target_entity_id is None else f"operative {self.target_entity_id}"
        prefix = "QUEUED" if self.queued else "LAST SIGNAL"
        return f"{prefix}: {self.name} / {target}"


class GlasshouseSoundCueKind(StrEnum):
    """The bounded presentation-only Glasshouse sound vocabulary."""

    FIRE = "fire"
    IMPACT = "impact"
    INJURY = "injury"
    OBJECTIVE_RETRIEVED = "objective_retrieved"
    OBJECTIVE_EXTRACTED = "objective_extracted"
    LOCKDOWN = "lockdown"


@dataclass(frozen=True, slots=True)
class GlasshouseSoundCue:
    """One event-identified audio request copied from an authority event."""

    event_id: int
    kind: GlasshouseSoundCueKind

    def __post_init__(self) -> None:
        if (
            not isinstance(self.event_id, int)
            or isinstance(self.event_id, bool)
            or self.event_id <= 0
        ):
            raise ValueError("Glasshouse sound cue event ID must be positive")
        if not isinstance(self.kind, GlasshouseSoundCueKind):
            raise TypeError("Glasshouse sound cue kind is invalid")


def build_glasshouse_sound_cues(
    events: tuple[CanonicalEvent, ...],
) -> tuple[GlasshouseSoundCue, ...]:
    """Copy the audible subset of one canonically ordered authority event tuple."""
    if not isinstance(events, tuple):
        raise TypeError("Glasshouse sound cues require immutable canonical events")
    if canonical_event_order(events) != events:
        raise ValueError("Glasshouse sound cues require canonical event order")
    cues: list[GlasshouseSoundCue] = []
    for event in events:
        kind = _sound_cue_kind(event_kind(event))
        if kind is not None:
            cues.append(GlasshouseSoundCue(event.header.event_id.value, kind))
    return tuple(cues)


def _sound_cue_kind(event: EventKind) -> GlasshouseSoundCueKind | None:
    if event is EventKind.FIRE_FIRED:
        return GlasshouseSoundCueKind.FIRE
    if event is EventKind.PROJECTILE_IMPACTED:
        return GlasshouseSoundCueKind.IMPACT
    if event is EventKind.INJURY_CHANGED:
        return GlasshouseSoundCueKind.INJURY
    if event is EventKind.OBJECTIVE_RETRIEVED:
        return GlasshouseSoundCueKind.OBJECTIVE_RETRIEVED
    if event is EventKind.OBJECTIVE_EXTRACTED:
        return GlasshouseSoundCueKind.OBJECTIVE_EXTRACTED
    if event is EventKind.LOCKDOWN_ACTIVATED:
        return GlasshouseSoundCueKind.LOCKDOWN
    return None


class GlasshouseMissionOutcome(StrEnum):
    """The read-only Glasshouse outcome projected from objective and lockdown state."""

    IN_PROGRESS = "in_progress"
    SUCCESS = "success"
    FAILURE = "failure"


@dataclass(frozen=True, slots=True)
class GlasshouseMissionSummary:
    """One concise mission status with no authority-state reference."""

    outcome: GlasshouseMissionOutcome
    objective_status: ObjectiveStatus
    lockdown_active: bool

    def __post_init__(self) -> None:
        if not isinstance(self.outcome, GlasshouseMissionOutcome):
            raise TypeError("Glasshouse mission summary outcome is invalid")
        if not isinstance(self.objective_status, ObjectiveStatus):
            raise TypeError("Glasshouse mission summary objective status is invalid")
        if not isinstance(self.lockdown_active, bool):
            raise TypeError("Glasshouse mission summary lockdown state must be boolean")

    @property
    def panel_line(self) -> str:
        """Return the terminal or current mission result for the mission HUD."""
        if self.outcome is GlasshouseMissionOutcome.SUCCESS:
            return "MISSION: SUCCESS / objective extracted"
        if self.outcome is GlasshouseMissionOutcome.FAILURE:
            return "MISSION: FAILURE / lockdown blocked extraction"
        return f"MISSION: IN PROGRESS / objective {self.objective_status.value}"


def build_glasshouse_mission_summary(
    objective_status: ObjectiveStatus, *, lockdown_active: bool
) -> GlasshouseMissionSummary:
    """Project the existing Glasshouse objective and lockdown facts into a HUD summary."""
    if not isinstance(objective_status, ObjectiveStatus):
        raise TypeError("Glasshouse mission summary requires an objective status")
    if not isinstance(lockdown_active, bool):
        raise TypeError("Glasshouse mission summary lockdown state must be boolean")
    if objective_status is ObjectiveStatus.EXTRACTED:
        outcome = GlasshouseMissionOutcome.SUCCESS
    elif lockdown_active:
        outcome = GlasshouseMissionOutcome.FAILURE
    else:
        outcome = GlasshouseMissionOutcome.IN_PROGRESS
    return GlasshouseMissionSummary(outcome, objective_status, lockdown_active)


@dataclass(frozen=True, slots=True)
class GlasshouseMissionPresentation:
    """One complete renderer input containing no authoritative mission-state reference."""

    snapshot: PresentationSnapshot
    summary: GlasshouseMissionSummary
    remaining_lockdown_ticks: int
    signal_status: GlasshouseSignalStatus | None
    sound_cues: tuple[GlasshouseSoundCue, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.snapshot, PresentationSnapshot):
            raise TypeError("Glasshouse mission presentation requires a snapshot")
        if not isinstance(self.summary, GlasshouseMissionSummary):
            raise TypeError("Glasshouse mission presentation summary is invalid")
        if (
            not isinstance(self.remaining_lockdown_ticks, int)
            or isinstance(self.remaining_lockdown_ticks, bool)
            or self.remaining_lockdown_ticks < 0
        ):
            raise ValueError("Glasshouse mission presentation lockdown ticks are invalid")
        if self.signal_status is not None and not isinstance(
            self.signal_status, GlasshouseSignalStatus
        ):
            raise TypeError("Glasshouse mission presentation signal status is invalid")
        if not isinstance(self.sound_cues, tuple) or any(
            not isinstance(cue, GlasshouseSoundCue) for cue in self.sound_cues
        ):
            raise TypeError("Glasshouse mission presentation sound cues are invalid")
        cue_ids = tuple(cue.event_id for cue in self.sound_cues)
        if cue_ids != tuple(sorted(cue_ids)) or len(set(cue_ids)) != len(cue_ids):
            raise ValueError("Glasshouse mission presentation sound cues must be event-ID ordered")

    @property
    def panel_lines(self) -> tuple[str, str, str, str, str]:
        """Return fixed-order mission HUD content from copied presentation data."""
        return (
            "GLASSHOUSE",
            self.summary.panel_line,
            f"PHASE: {self.snapshot.phase}  TICK: {self.snapshot.tick}",
            f"LOCKDOWN: T-{self.remaining_lockdown_ticks} ticks",
            "SIGNALS: advance / hold"
            if self.signal_status is None
            else self.signal_status.panel_line,
        )
