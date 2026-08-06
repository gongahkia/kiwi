"""Read-only Glasshouse mission HUD values derived outside the renderer."""

from __future__ import annotations

from dataclasses import dataclass

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


@dataclass(frozen=True, slots=True)
class GlasshouseMissionPresentation:
    """One complete renderer input containing no authoritative mission-state reference."""

    snapshot: PresentationSnapshot
    remaining_lockdown_ticks: int
    signal_status: GlasshouseSignalStatus | None

    def __post_init__(self) -> None:
        if not isinstance(self.snapshot, PresentationSnapshot):
            raise TypeError("Glasshouse mission presentation requires a snapshot")
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

    @property
    def panel_lines(self) -> tuple[str, str, str, str]:
        """Return fixed-order mission HUD content from copied presentation data."""
        return (
            "GLASSHOUSE",
            f"PHASE: {self.snapshot.phase}  TICK: {self.snapshot.tick}",
            f"LOCKDOWN: T-{self.remaining_lockdown_ticks} ticks",
            "SIGNALS: advance / hold"
            if self.signal_status is None
            else self.signal_status.panel_line,
        )
