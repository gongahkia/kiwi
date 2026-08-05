"""Canonical event emission for deterministic firing and projectile consequences."""

from __future__ import annotations

from dataclasses import dataclass, replace

from kiwi.domain.ids import EventId, IntentionId, ProjectileId
from kiwi.sim.damage import DamagePhase
from kiwi.sim.events import (
    CanonicalEvent,
    DamageApplied,
    EventHeader,
    FireFired,
    FireRejected,
    InjuryChanged,
    IntentionSelected,
    ProjectileAdvanced,
    ProjectileExpired,
    ProjectileImpacted,
    SuppressionChanged,
    canonical_event_order,
)
from kiwi.sim.firing import FireExecutionPhase, FireResolutionStatus
from kiwi.sim.projectile_impacts import ProjectileImpactPhase, ProjectileResolutionKind
from kiwi.sim.state import MissionState
from kiwi.sim.suppression import SuppressionPhase


@dataclass(frozen=True, slots=True)
class CombatEventPhase:
    """One successor allocation state and canonically ordered combat events."""

    state: MissionState
    events: tuple[CanonicalEvent, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("combat event phase requires mission state")
        if not isinstance(self.events, tuple):
            raise ValueError("combat event phase events must be an immutable tuple")
        if canonical_event_order(self.events) != self.events:
            raise ValueError("combat event phase events must be canonically ordered")


def emit_fire_events(
    phase: FireExecutionPhase,
    policy_events: tuple[CanonicalEvent, ...],
) -> CombatEventPhase:
    """Emit one selected-fire outcome event per intention-ID-ordered resolution."""
    if not isinstance(phase, FireExecutionPhase):
        raise TypeError("fire event emission requires a fire execution phase")
    if not isinstance(policy_events, tuple):
        raise TypeError("fire event emission requires immutable policy events")
    next_state = phase.state
    events: list[CanonicalEvent] = []
    for resolution in phase.resolutions:
        selected_event_id = _selected_event_id(
            policy_events,
            resolution.candidate.origin.intention_id,
        )
        next_state, header = _allocate_event_header(next_state, (selected_event_id,))
        if resolution.status is FireResolutionStatus.FIRED:
            events.append(FireFired(header, resolution))
        else:
            events.append(FireRejected(header, resolution))
    return CombatEventPhase(next_state, tuple(events))


def emit_projectile_events(phase: ProjectileImpactPhase) -> CombatEventPhase:
    """Emit one projectile advancement, expiry, or impact event per resolution."""
    if not isinstance(phase, ProjectileImpactPhase):
        raise TypeError("projectile event emission requires a projectile impact phase")
    next_state = phase.state
    events: list[CanonicalEvent] = []
    for resolution in phase.resolutions:
        next_state, header = _allocate_event_header(next_state)
        if resolution.kind is ProjectileResolutionKind.ADVANCED:
            events.append(ProjectileAdvanced(header, resolution))
        elif resolution.kind is ProjectileResolutionKind.EXPIRED:
            events.append(ProjectileExpired(header, resolution))
        elif resolution.kind is ProjectileResolutionKind.IMPACTED:
            if resolution.impact is None:
                raise AssertionError("impacted projectile resolution must retain an impact")
            events.append(ProjectileImpacted(header, resolution.impact))
        else:
            raise AssertionError("projectile resolution kind is unsupported")
    return CombatEventPhase(next_state, tuple(events))


def emit_damage_events(
    phase: DamagePhase,
    projectile_events: tuple[CanonicalEvent, ...],
) -> CombatEventPhase:
    """Emit damage and injury-boundary events in projectile-ID order."""
    if not isinstance(phase, DamagePhase):
        raise TypeError("damage event emission requires a damage phase")
    if not isinstance(projectile_events, tuple):
        raise TypeError("damage event emission requires immutable projectile events")
    next_state = phase.state
    events: list[CanonicalEvent] = []
    for resolution in phase.resolutions:
        impact_event_id = _impact_event_id(
            projectile_events,
            resolution.impact.projectile.projectile_id,
        )
        next_state, damage_header = _allocate_event_header(next_state, (impact_event_id,))
        damage_event = DamageApplied(damage_header, resolution)
        events.append(damage_event)
        if resolution.injury_before is not resolution.injury_after:
            next_state, injury_header = _allocate_event_header(
                next_state,
                (damage_event.header.event_id,),
            )
            events.append(InjuryChanged(injury_header, resolution))
    return CombatEventPhase(next_state, tuple(events))


def emit_suppression_events(
    phase: SuppressionPhase,
    projectile_events: tuple[CanonicalEvent, ...],
) -> CombatEventPhase:
    """Emit changed suppression records with exact current-tick projectile parents."""
    if not isinstance(phase, SuppressionPhase):
        raise TypeError("suppression event emission requires a suppression phase")
    if not isinstance(projectile_events, tuple):
        raise TypeError("suppression event emission requires immutable projectile events")
    next_state = phase.state
    events: list[CanonicalEvent] = []
    for resolution in phase.resolutions:
        if resolution.suppression_before == resolution.suppression_after:
            continue
        projectile_ids = tuple(
            contribution.projectile.projectile_id for contribution in resolution.contributions
        )
        parent_event_ids = _projectile_event_ids(projectile_events, projectile_ids)
        next_state, header = _allocate_event_header(next_state, parent_event_ids)
        events.append(SuppressionChanged(header, resolution))
    return CombatEventPhase(next_state, tuple(events))


def _selected_event_id(events: tuple[CanonicalEvent, ...], intention_id: IntentionId) -> EventId:
    for event in events:
        if (
            isinstance(event, IntentionSelected)
            and event.resolution.candidate.origin.intention_id == intention_id
        ):
            return event.header.event_id
    raise ValueError("fire event emission requires a selected intention event")


def _impact_event_id(events: tuple[CanonicalEvent, ...], projectile_id: ProjectileId) -> EventId:
    for event in events:
        if (
            isinstance(event, ProjectileImpacted)
            and event.impact.projectile.projectile_id == projectile_id
        ):
            return event.header.event_id
    raise ValueError("damage event emission requires a projectile impact event")


def _projectile_event_ids(
    events: tuple[CanonicalEvent, ...],
    projectile_ids: tuple[ProjectileId, ...],
) -> tuple[EventId, ...]:
    event_ids: list[EventId] = []
    for projectile_id in projectile_ids:
        event_id = _projectile_event_id(events, projectile_id)
        if event_id not in event_ids:
            event_ids.append(event_id)
    return tuple(sorted(event_ids, key=lambda event_id: event_id.value))


def _projectile_event_id(
    events: tuple[CanonicalEvent, ...], projectile_id: ProjectileId
) -> EventId:
    for event in events:
        if isinstance(event, ProjectileAdvanced):
            resolved_id = event.resolution.projectile.projectile_id
        elif isinstance(event, ProjectileExpired):
            resolved_id = event.resolution.projectile.projectile_id
        elif isinstance(event, ProjectileImpacted):
            resolved_id = event.impact.projectile.projectile_id
        else:
            continue
        if resolved_id == projectile_id:
            return event.header.event_id
    raise ValueError("suppression event emission requires a projectile outcome event")


def _allocate_event_header(
    state: MissionState,
    parent_event_ids: tuple[EventId, ...] = (),
) -> tuple[MissionState, EventHeader]:
    event_id, id_allocator = state.id_allocator.allocate_event()
    return replace(state, id_allocator=id_allocator), EventHeader(
        event_id,
        state.tick,
        parent_event_ids,
    )
