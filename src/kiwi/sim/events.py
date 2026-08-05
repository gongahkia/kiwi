"""Closed canonical authority event records."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from enum import StrEnum
from typing import TYPE_CHECKING

from kiwi.domain.ids import EventId
from kiwi.sim.arbitration import (
    ArbitrationStatus,
    IntentionArbitration,
    IntentionCandidate,
)
from kiwi.sim.commands import ExternalCommand, IssueSignal, RequestAbort, StartMission
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.movement import MovementResolution, MovementResolutionKind
from kiwi.sim.pathing import Path, PathQueryFailure, PathSearchFailure
from kiwi.sim.policies import PolicyValidation
from kiwi.sim.randomness import RandomDraw
from kiwi.sim.scheduled import ScheduledEvent

if TYPE_CHECKING:
    from kiwi.sim.cover_intentions import TakeCoverResolution
    from kiwi.sim.covers import CoverReservation
    from kiwi.sim.damage import DamageResolution
    from kiwi.sim.firing import FireResolution
    from kiwi.sim.intentions import IntentionOrigin
    from kiwi.sim.messages import Message
    from kiwi.sim.projectile_impacts import ProjectileImpact, ProjectileResolution
    from kiwi.sim.suppression import SuppressionResolution


class EventKind(StrEnum):
    """The current closed set of canonical authority event variants."""

    MISSION_STARTED = "mission_started"
    ABORT_REQUESTED = "abort_requested"
    SIGNAL_ISSUED = "signal_issued"
    MESSAGE_SENT = "message_sent"
    MESSAGE_DELIVERED = "message_delivered"
    SCHEDULED_TRIGGER_FIRED = "scheduled_trigger_fired"
    RANDOM_DRAW_RECORDED = "random_draw_recorded"
    COMMAND_REJECTED = "command_rejected"
    POLICY_EVALUATED = "policy_evaluated"
    INTENTION_EMITTED = "intention_emitted"
    INTENTION_SELECTED = "intention_selected"
    INTENTION_REJECTED = "intention_rejected"
    COVER_RESERVATION_GRANTED = "cover_reservation_granted"
    COVER_RESERVATION_REJECTED = "cover_reservation_rejected"
    MOVEMENT_PROGRESSED = "movement_progressed"
    MOVEMENT_BLOCKED = "movement_blocked"
    MOVEMENT_ARRIVED = "movement_arrived"
    MOVEMENT_ROUTE_STARTED = "movement_route_started"
    MOVEMENT_ROUTE_REJECTED = "movement_route_rejected"
    FIRE_FIRED = "fire_fired"
    FIRE_REJECTED = "fire_rejected"
    PROJECTILE_ADVANCED = "projectile_advanced"
    PROJECTILE_EXPIRED = "projectile_expired"
    PROJECTILE_IMPACTED = "projectile_impacted"
    DAMAGE_APPLIED = "damage_applied"
    INJURY_CHANGED = "injury_changed"
    SUPPRESSION_CHANGED = "suppression_changed"


class CommandRejectionReason(StrEnum):
    """Stable reasons the initial reducer can reject an external command."""

    MISSION_NOT_PREPARED = "mission_not_prepared"
    MISSION_NOT_ACTIVE = "mission_not_active"
    SIGNAL_TARGET_NOT_FOUND = "signal_target_not_found"


@dataclass(frozen=True, slots=True)
class EventHeader:
    """Stable event identity, timestamp, and canonical causal parents."""

    event_id: EventId
    tick: int
    parent_event_ids: tuple[EventId, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.event_id, EventId):
            raise ValueError("event header requires an event ID")
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("event tick must be an integer")
        if not 0 <= self.tick <= MAX_AUTHORITY_TICK:
            raise ValueError("event tick must fit non-negative signed 64-bit range")
        if not isinstance(self.parent_event_ids, tuple):
            raise ValueError("event parent IDs must be an immutable tuple")
        previous_id = 0
        for parent_id in self.parent_event_ids:
            if not isinstance(parent_id, EventId):
                raise ValueError("event parent IDs must contain event IDs")
            if parent_id.value <= previous_id:
                raise ValueError("event parent IDs must be unique and ascending")
            if parent_id.value >= self.event_id.value:
                raise ValueError("event parent IDs must precede the event ID")
            previous_id = parent_id.value


@dataclass(frozen=True, slots=True)
class MissionStarted:
    """The recorded application of a start-mission command."""

    header: EventHeader
    command: StartMission

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.command, StartMission):
            raise ValueError("mission started event requires a start mission command")
        _require_matching_tick(self.header, self.command.header.tick)


@dataclass(frozen=True, slots=True)
class AbortRequested:
    """The recorded application of an abort request command."""

    header: EventHeader
    command: RequestAbort

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.command, RequestAbort):
            raise ValueError("abort event requires an abort request command")
        _require_matching_tick(self.header, self.command.header.tick)


@dataclass(frozen=True, slots=True)
class SignalIssued:
    """The recorded application of a high-level signal command."""

    header: EventHeader
    command: IssueSignal

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.command, IssueSignal):
            raise ValueError("signal event requires a signal command")
        _require_matching_tick(self.header, self.command.header.tick)


@dataclass(frozen=True, slots=True)
class MessageSent:
    """The authoritative send record for one immutable message."""

    header: EventHeader
    message: Message

    def __post_init__(self) -> None:
        from kiwi.sim.messages import Message

        _require_header(self.header)
        if not isinstance(self.message, Message):
            raise ValueError("message send event requires a message")
        _require_matching_tick(self.header, self.message.send_tick)
        if self.header.event_id != self.message.send_event_id:
            raise ValueError("message send event ID must match its message")
        if self.header.parent_event_ids != self.message.provenance_event_ids:
            raise ValueError("message send event parents must match message provenance")


@dataclass(frozen=True, slots=True)
class MessageDelivered:
    """The authoritative delivery record causally linked to one message send."""

    header: EventHeader
    message: Message

    def __post_init__(self) -> None:
        from kiwi.sim.messages import Message

        _require_header(self.header)
        if not isinstance(self.message, Message):
            raise ValueError("message delivery event requires a message")
        _require_matching_tick(self.header, self.message.delivery_tick)
        if self.header.parent_event_ids != (self.message.send_event_id,):
            raise ValueError("message delivery event must parent its message send")


@dataclass(frozen=True, slots=True)
class ScheduledTriggerFired:
    """The recorded dequeue of one scheduled scenario trigger."""

    header: EventHeader
    scheduled_event: ScheduledEvent

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.scheduled_event, ScheduledEvent):
            raise ValueError("scheduled trigger event requires a scheduled event")
        _require_matching_tick(self.header, self.scheduled_event.tick)


@dataclass(frozen=True, slots=True)
class RandomDrawRecorded:
    """The recorded use of one named deterministic random draw."""

    header: EventHeader
    draw: RandomDraw

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.draw, RandomDraw):
            raise ValueError("random draw event requires a random draw")


@dataclass(frozen=True, slots=True)
class CommandRejected:
    """A structured record of an invalid or unsupported command application."""

    header: EventHeader
    command: ExternalCommand
    reason: CommandRejectionReason

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.command, (StartMission, RequestAbort, IssueSignal)):
            raise ValueError("command rejection event requires an external command")
        if not isinstance(self.reason, CommandRejectionReason):
            raise ValueError("command rejection event requires a rejection reason")
        _require_matching_tick(self.header, self.command.header.tick)


@dataclass(frozen=True, slots=True)
class PolicyEvaluated:
    """The retained result of one policy invocation and boundary validation."""

    header: EventHeader
    validation: PolicyValidation

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.validation, PolicyValidation):
            raise ValueError("policy evaluated event requires a policy validation")
        _require_matching_tick(self.header, self.validation.evaluation.observation.tick)


@dataclass(frozen=True, slots=True)
class IntentionEmitted:
    """One source-linked validated candidate returned by a policy."""

    header: EventHeader
    candidate: IntentionCandidate

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.candidate, IntentionCandidate):
            raise ValueError("intention emitted event requires an intention candidate")
        _require_matching_tick(self.header, self.candidate.origin.creation_tick)


@dataclass(frozen=True, slots=True)
class IntentionSelected:
    """The canonical selection of one emitted candidate."""

    header: EventHeader
    resolution: IntentionArbitration

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.resolution, IntentionArbitration):
            raise ValueError("intention selected event requires an arbitration")
        if self.resolution.status is not ArbitrationStatus.SELECTED:
            raise ValueError("intention selected event requires a selected arbitration")
        _require_matching_tick(self.header, self.resolution.candidate.origin.creation_tick)


@dataclass(frozen=True, slots=True)
class IntentionRejected:
    """The canonical rejection of one emitted candidate."""

    header: EventHeader
    resolution: IntentionArbitration

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.resolution, IntentionArbitration):
            raise ValueError("intention rejected event requires an arbitration")
        if self.resolution.status is not ArbitrationStatus.REJECTED:
            raise ValueError("intention rejected event requires a rejected arbitration")
        _require_matching_tick(self.header, self.resolution.candidate.origin.creation_tick)


@dataclass(frozen=True, slots=True)
class CoverReservationGranted:
    """The source-linked grant of one selected TakeCover reservation."""

    header: EventHeader
    resolution: TakeCoverResolution
    reservation: CoverReservation

    def __post_init__(self) -> None:
        from kiwi.sim.cover_intentions import TakeCoverResolution
        from kiwi.sim.covers import CoverReservation, CoverReservationStatus

        _require_header(self.header)
        if not isinstance(self.resolution, TakeCoverResolution):
            raise ValueError("cover reservation grant requires a take-cover resolution")
        if self.resolution.status is not CoverReservationStatus.GRANTED:
            raise ValueError("cover reservation grant requires a granted resolution")
        if not isinstance(self.reservation, CoverReservation):
            raise ValueError("cover reservation grant requires a cover reservation")
        if len(self.header.parent_event_ids) != 1:
            raise ValueError("cover reservation grant requires one selected-intention parent")
        if self.reservation.entity_id != self.resolution.candidate.origin.issuer_entity_id:
            raise ValueError("cover reservation grant owner must match its intention issuer")
        if self.reservation.intention_id != self.resolution.candidate.origin.intention_id:
            raise ValueError("cover reservation grant intention must match its resolution")
        if self.reservation.slot_index != self.resolution.slot_index:
            raise ValueError("cover reservation grant slot must match its resolution")
        _require_matching_tick(self.header, self.resolution.candidate.origin.creation_tick)


@dataclass(frozen=True, slots=True)
class CoverReservationRejected:
    """The source-linked rejection of one selected TakeCover reservation."""

    header: EventHeader
    resolution: TakeCoverResolution

    def __post_init__(self) -> None:
        from kiwi.sim.cover_intentions import TakeCoverResolution
        from kiwi.sim.covers import CoverReservationStatus

        _require_header(self.header)
        if not isinstance(self.resolution, TakeCoverResolution):
            raise ValueError("cover reservation rejection requires a take-cover resolution")
        if self.resolution.status is not CoverReservationStatus.REJECTED:
            raise ValueError("cover reservation rejection requires a rejected resolution")
        if len(self.header.parent_event_ids) != 1:
            raise ValueError("cover reservation rejection requires one selected-intention parent")
        _require_matching_tick(self.header, self.resolution.candidate.origin.creation_tick)


@dataclass(frozen=True, slots=True)
class MovementRouteStarted:
    """One selected move request whose canonical route was activated."""

    header: EventHeader
    candidate: IntentionCandidate
    path: Path

    def __post_init__(self) -> None:
        from kiwi.sim.intentions import MoveTowardIntention

        _require_header(self.header)
        if not isinstance(self.candidate, IntentionCandidate):
            raise ValueError("movement route start requires an intention candidate")
        if not isinstance(self.candidate.intention, MoveTowardIntention):
            raise ValueError("movement route start requires a move-toward intention")
        if not isinstance(self.path, Path):
            raise ValueError("movement route start requires a path")
        if (
            self.path.query.goal.x != self.candidate.intention.target.x
            or self.path.query.goal.y != self.candidate.intention.target.y
        ):
            raise ValueError("movement route target must match the selected intention")
        _require_matching_tick(self.header, self.candidate.origin.creation_tick)


@dataclass(frozen=True, slots=True)
class MovementRouteRejected:
    """One selected move request with a structured route-planning failure."""

    header: EventHeader
    candidate: IntentionCandidate
    failure: PathQueryFailure | PathSearchFailure

    def __post_init__(self) -> None:
        from kiwi.sim.intentions import MoveTowardIntention

        _require_header(self.header)
        if not isinstance(self.candidate, IntentionCandidate):
            raise ValueError("movement route rejection requires an intention candidate")
        if not isinstance(self.candidate.intention, MoveTowardIntention):
            raise ValueError("movement route rejection requires a move-toward intention")
        if not isinstance(self.failure, (PathQueryFailure, PathSearchFailure)):
            raise ValueError("movement route rejection requires a path failure")
        _require_matching_tick(self.header, self.candidate.origin.creation_tick)


@dataclass(frozen=True, slots=True)
class MovementProgressed:
    """One accepted non-final movement segment advance."""

    header: EventHeader
    resolution: MovementResolution

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.resolution, MovementResolution):
            raise ValueError("movement progress event requires a movement resolution")
        if self.resolution.kind is not MovementResolutionKind.PROGRESSED:
            raise ValueError("movement progress event requires a progressed resolution")
        _require_matching_tick(self.header, self.resolution.tick)


@dataclass(frozen=True, slots=True)
class MovementBlocked:
    """One held movement action with a structured collision reason."""

    header: EventHeader
    resolution: MovementResolution

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.resolution, MovementResolution):
            raise ValueError("movement block event requires a movement resolution")
        if self.resolution.kind is not MovementResolutionKind.BLOCKED:
            raise ValueError("movement block event requires a blocked resolution")
        _require_matching_tick(self.header, self.resolution.tick)


@dataclass(frozen=True, slots=True)
class MovementArrived:
    """One movement action that reached its final path waypoint."""

    header: EventHeader
    resolution: MovementResolution

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.resolution, MovementResolution):
            raise ValueError("movement arrival event requires a movement resolution")
        if self.resolution.kind is not MovementResolutionKind.ARRIVED:
            raise ValueError("movement arrival event requires an arrived resolution")
        _require_matching_tick(self.header, self.resolution.tick)


@dataclass(frozen=True, slots=True)
class FireFired:
    """One successful selected fire request and its spawned projectile."""

    header: EventHeader
    resolution: FireResolution

    def __post_init__(self) -> None:
        from kiwi.sim.firing import FireResolution, FireResolutionStatus

        _require_header(self.header)
        if not isinstance(self.resolution, FireResolution):
            raise ValueError("fire event requires a fire resolution")
        if self.resolution.status is not FireResolutionStatus.FIRED:
            raise ValueError("fired event requires a fired resolution")
        if len(self.header.parent_event_ids) != 1:
            raise ValueError("fired event requires one selected-intention parent")
        _require_matching_tick(self.header, self.resolution.candidate.origin.creation_tick)


@dataclass(frozen=True, slots=True)
class FireRejected:
    """One selected fire request rejected by current authority state."""

    header: EventHeader
    resolution: FireResolution

    def __post_init__(self) -> None:
        from kiwi.sim.firing import FireResolution, FireResolutionStatus

        _require_header(self.header)
        if not isinstance(self.resolution, FireResolution):
            raise ValueError("fire rejection event requires a fire resolution")
        if self.resolution.status is not FireResolutionStatus.REJECTED:
            raise ValueError("fire rejection event requires a rejected resolution")
        if len(self.header.parent_event_ids) != 1:
            raise ValueError("fire rejection event requires one selected-intention parent")
        _require_matching_tick(self.header, self.resolution.candidate.origin.creation_tick)


@dataclass(frozen=True, slots=True)
class ProjectileAdvanced:
    """One live projectile that travelled one unobstructed nonterminal segment."""

    header: EventHeader
    resolution: ProjectileResolution

    def __post_init__(self) -> None:
        from kiwi.sim.projectile_impacts import ProjectileResolution, ProjectileResolutionKind

        _require_header(self.header)
        if not isinstance(self.resolution, ProjectileResolution):
            raise ValueError("projectile advance event requires a projectile resolution")
        if self.resolution.kind is not ProjectileResolutionKind.ADVANCED:
            raise ValueError("projectile advance event requires an advanced resolution")
        _require_matching_tick(self.header, self.resolution.tick)


@dataclass(frozen=True, slots=True)
class ProjectileExpired:
    """One terminal-lifetime projectile that travelled its final clear segment."""

    header: EventHeader
    resolution: ProjectileResolution

    def __post_init__(self) -> None:
        from kiwi.sim.projectile_impacts import ProjectileResolution, ProjectileResolutionKind

        _require_header(self.header)
        if not isinstance(self.resolution, ProjectileResolution):
            raise ValueError("projectile expiry event requires a projectile resolution")
        if self.resolution.kind is not ProjectileResolutionKind.EXPIRED:
            raise ValueError("projectile expiry event requires an expired resolution")
        _require_matching_tick(self.header, self.resolution.tick)


@dataclass(frozen=True, slots=True)
class ProjectileImpacted:
    """One projectile collision with its exact selected collision result."""

    header: EventHeader
    impact: ProjectileImpact

    def __post_init__(self) -> None:
        from kiwi.sim.projectile_impacts import ProjectileImpact

        _require_header(self.header)
        if not isinstance(self.impact, ProjectileImpact):
            raise ValueError("projectile impact event requires a projectile impact")
        _require_matching_tick(self.header, self.impact.tick)


@dataclass(frozen=True, slots=True)
class DamageApplied:
    """One deterministic protection and health result from an operative impact."""

    header: EventHeader
    resolution: DamageResolution

    def __post_init__(self) -> None:
        from kiwi.sim.damage import DamageResolution

        _require_header(self.header)
        if not isinstance(self.resolution, DamageResolution):
            raise ValueError("damage event requires a damage resolution")
        if len(self.header.parent_event_ids) != 1:
            raise ValueError("damage event requires one projectile-impact parent")
        _require_matching_tick(self.header, self.resolution.impact.tick)


@dataclass(frozen=True, slots=True)
class InjuryChanged:
    """One damage result that crossed a stable injury-severity boundary."""

    header: EventHeader
    resolution: DamageResolution

    def __post_init__(self) -> None:
        from kiwi.sim.damage import DamageResolution

        _require_header(self.header)
        if not isinstance(self.resolution, DamageResolution):
            raise ValueError("injury event requires a damage resolution")
        if self.resolution.injury_before is self.resolution.injury_after:
            raise ValueError("injury event requires a changed injury severity")
        if len(self.header.parent_event_ids) != 1:
            raise ValueError("injury event requires one damage parent")
        _require_matching_tick(self.header, self.resolution.impact.tick)

    @property
    def source_intention(self) -> IntentionOrigin:
        """Return the Fire origin retained through the injury consequence."""
        return self.resolution.source_intention


@dataclass(frozen=True, slots=True)
class SuppressionChanged:
    """One nonzero suppression-state change and its retained physical sources."""

    header: EventHeader
    resolution: SuppressionResolution

    def __post_init__(self) -> None:
        from kiwi.sim.suppression import SuppressionResolution

        _require_header(self.header)
        if not isinstance(self.resolution, SuppressionResolution):
            raise ValueError("suppression event requires a suppression resolution")
        if self.resolution.suppression_before == self.resolution.suppression_after:
            raise ValueError("suppression event requires a changed suppression value")
        if self.resolution.contributions and not self.header.parent_event_ids:
            raise ValueError("suppression source contributions require projectile outcome parents")
        _require_matching_tick(self.header, self.resolution.tick)


CanonicalEvent = (
    MissionStarted
    | AbortRequested
    | SignalIssued
    | MessageSent
    | MessageDelivered
    | ScheduledTriggerFired
    | RandomDrawRecorded
    | CommandRejected
    | PolicyEvaluated
    | IntentionEmitted
    | IntentionSelected
    | IntentionRejected
    | CoverReservationGranted
    | CoverReservationRejected
    | MovementRouteStarted
    | MovementRouteRejected
    | MovementProgressed
    | MovementBlocked
    | MovementArrived
    | FireFired
    | FireRejected
    | ProjectileAdvanced
    | ProjectileExpired
    | ProjectileImpacted
    | DamageApplied
    | InjuryChanged
    | SuppressionChanged
)


def event_kind(event: CanonicalEvent) -> EventKind:
    """Return the stable tag for a closed event variant."""
    if isinstance(event, MissionStarted):
        return EventKind.MISSION_STARTED
    if isinstance(event, AbortRequested):
        return EventKind.ABORT_REQUESTED
    if isinstance(event, SignalIssued):
        return EventKind.SIGNAL_ISSUED
    if isinstance(event, MessageSent):
        return EventKind.MESSAGE_SENT
    if isinstance(event, MessageDelivered):
        return EventKind.MESSAGE_DELIVERED
    if isinstance(event, ScheduledTriggerFired):
        return EventKind.SCHEDULED_TRIGGER_FIRED
    if isinstance(event, RandomDrawRecorded):
        return EventKind.RANDOM_DRAW_RECORDED
    if isinstance(event, CommandRejected):
        return EventKind.COMMAND_REJECTED
    if isinstance(event, PolicyEvaluated):
        return EventKind.POLICY_EVALUATED
    if isinstance(event, IntentionEmitted):
        return EventKind.INTENTION_EMITTED
    if isinstance(event, IntentionSelected):
        return EventKind.INTENTION_SELECTED
    if isinstance(event, IntentionRejected):
        return EventKind.INTENTION_REJECTED
    if isinstance(event, CoverReservationGranted):
        return EventKind.COVER_RESERVATION_GRANTED
    if isinstance(event, CoverReservationRejected):
        return EventKind.COVER_RESERVATION_REJECTED
    if isinstance(event, MovementRouteStarted):
        return EventKind.MOVEMENT_ROUTE_STARTED
    if isinstance(event, MovementRouteRejected):
        return EventKind.MOVEMENT_ROUTE_REJECTED
    if isinstance(event, MovementProgressed):
        return EventKind.MOVEMENT_PROGRESSED
    if isinstance(event, MovementBlocked):
        return EventKind.MOVEMENT_BLOCKED
    if isinstance(event, MovementArrived):
        return EventKind.MOVEMENT_ARRIVED
    if isinstance(event, FireFired):
        return EventKind.FIRE_FIRED
    if isinstance(event, FireRejected):
        return EventKind.FIRE_REJECTED
    if isinstance(event, ProjectileAdvanced):
        return EventKind.PROJECTILE_ADVANCED
    if isinstance(event, ProjectileExpired):
        return EventKind.PROJECTILE_EXPIRED
    if isinstance(event, ProjectileImpacted):
        return EventKind.PROJECTILE_IMPACTED
    if isinstance(event, DamageApplied):
        return EventKind.DAMAGE_APPLIED
    if isinstance(event, InjuryChanged):
        return EventKind.INJURY_CHANGED
    if isinstance(event, SuppressionChanged):
        return EventKind.SUPPRESSION_CHANGED
    raise ValueError("event kind requires a canonical event")


def canonical_event_order(events: Iterable[CanonicalEvent]) -> tuple[CanonicalEvent, ...]:
    """Sort canonical events by `(tick, event ID)` and reject reused IDs."""
    ordered: list[CanonicalEvent] = []
    event_ids: set[int] = set()
    for event in events:
        if not isinstance(
            event,
            (
                MissionStarted,
                AbortRequested,
                SignalIssued,
                MessageSent,
                MessageDelivered,
                ScheduledTriggerFired,
                RandomDrawRecorded,
                CommandRejected,
                PolicyEvaluated,
                IntentionEmitted,
                IntentionSelected,
                IntentionRejected,
                CoverReservationGranted,
                CoverReservationRejected,
                MovementRouteStarted,
                MovementRouteRejected,
                MovementProgressed,
                MovementBlocked,
                MovementArrived,
                FireFired,
                FireRejected,
                ProjectileAdvanced,
                ProjectileExpired,
                ProjectileImpacted,
                DamageApplied,
                InjuryChanged,
                SuppressionChanged,
            ),
        ):
            raise ValueError("canonical event ordering requires canonical events")
        event_id = event.header.event_id.value
        if event_id in event_ids:
            raise ValueError("canonical event IDs must be globally unique")
        event_ids.add(event_id)
        ordered.append(event)
    return tuple(
        sorted(ordered, key=lambda event: (event.header.tick, event.header.event_id.value))
    )


def _require_header(value: object) -> None:
    if not isinstance(value, EventHeader):
        raise ValueError("event requires an event header")


def _require_matching_tick(header: EventHeader, source_tick: int) -> None:
    if header.tick != source_tick:
        raise ValueError("event tick must match its source tick")
