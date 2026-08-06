"""Minimal immutable authoritative mission state."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from kiwi.domain.geometry import WorldPosition, WorldSubunits, round_nearest_ties_away_from_zero
from kiwi.domain.ids import EntityId, EventId, IdAllocator, IdKind
from kiwi.sim.conditions import OperativeConditionStore
from kiwi.sim.contacts import ContactStore
from kiwi.sim.covers import CoverReservationStore, CoverStore
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.map_geometry import MapGeometry
from kiwi.sim.memory import PolicyMemoryStore
from kiwi.sim.messages import MessageLedger
from kiwi.sim.objectives import ObjectiveStore
from kiwi.sim.pathing import Path
from kiwi.sim.policy_versions import PolicyVersionStore
from kiwi.sim.projectiles import ProjectileStore
from kiwi.sim.randomness import RandomStreams, default_random_streams
from kiwi.sim.scheduled import ScheduledEventQueue
from kiwi.sim.signals import SignalStore
from kiwi.sim.weapons import AimStore, SuppressionStore, WeaponStore

MAX_MISSION_TICK = MAX_AUTHORITY_TICK


class MissionPhase(StrEnum):
    """The minimal authoritative mission lifecycle."""

    PREPARED = "prepared"
    ACTIVE = "active"
    ABORT_REQUESTED = "abort_requested"


@dataclass(frozen=True, slots=True)
class EntityState:
    """The minimal authoritative state shared by every world entity."""

    entity_id: EntityId
    position: WorldPosition

    def __post_init__(self) -> None:
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("entity state requires an entity ID")
        if not isinstance(self.position, WorldPosition):
            raise ValueError("entity state requires a world position")


@dataclass(frozen=True, slots=True)
class MovementAction:
    """One entity's in-progress path and exact dominant-axis segment progress."""

    entity_id: EntityId
    path: Path
    next_waypoint_index: int = 1
    segment_progress: int = 0
    origin_event_id: EventId | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("movement action requires an entity ID")
        if not isinstance(self.path, Path):
            raise ValueError("movement action requires a path")
        if len(self.path.waypoints) < 2:
            raise ValueError("movement action path must have a pending waypoint")
        if (
            not isinstance(self.next_waypoint_index, int)
            or isinstance(self.next_waypoint_index, bool)
            or not 1 <= self.next_waypoint_index < len(self.path.waypoints)
        ):
            raise ValueError("movement action next waypoint index is outside the path")
        if (
            not isinstance(self.segment_progress, int)
            or isinstance(self.segment_progress, bool)
            or not 0 <= self.segment_progress < movement_action_segment_length(self)
        ):
            raise ValueError("movement action segment progress is outside the active segment")
        if self.origin_event_id is not None and not isinstance(self.origin_event_id, EventId):
            raise ValueError("movement action origin event must be an event ID or absent")


def movement_action_segment_length(action: MovementAction) -> int:
    """Return the exact dominant-axis subunit length of the active segment."""
    if not isinstance(action, MovementAction):
        raise ValueError("movement segment length requires a movement action")
    start, goal = _movement_action_segment(action)
    return max(abs(goal.x.value - start.x.value), abs(goal.y.value - start.y.value))


def movement_action_position(action: MovementAction) -> WorldPosition:
    """Return the canonical current position for an action's segment progress."""
    if not isinstance(action, MovementAction):
        raise ValueError("movement action position requires a movement action")
    start, goal = _movement_action_segment(action)
    length = movement_action_segment_length(action)
    return WorldPosition(
        WorldSubunits(
            start.x.value
            + round_nearest_ties_away_from_zero(
                (goal.x.value - start.x.value) * action.segment_progress,
                length,
            )
        ),
        WorldSubunits(
            start.y.value
            + round_nearest_ties_away_from_zero(
                (goal.y.value - start.y.value) * action.segment_progress,
                length,
            )
        ),
        start.elevation,
    )


def _movement_action_segment(action: MovementAction) -> tuple[WorldPosition, WorldPosition]:
    return (
        action.path.waypoints[action.next_waypoint_index - 1],
        action.path.waypoints[action.next_waypoint_index],
    )


@dataclass(frozen=True, slots=True)
class MissionState:
    """The canonical state fields defined by the initial simulation kernel."""

    tick: int = 0
    phase: MissionPhase = MissionPhase.PREPARED
    entities: tuple[EntityState, ...] = ()
    map_geometry: MapGeometry | None = None
    movement_actions: tuple[MovementAction, ...] = ()
    id_allocator: IdAllocator = field(default_factory=IdAllocator)
    policy_memory: PolicyMemoryStore = field(default_factory=PolicyMemoryStore)
    policy_versions: PolicyVersionStore = field(default_factory=PolicyVersionStore)
    covers: CoverStore = field(default_factory=CoverStore)
    cover_reservations: CoverReservationStore = field(default_factory=CoverReservationStore)
    weapons: WeaponStore = field(default_factory=WeaponStore)
    aim_states: AimStore = field(default_factory=AimStore)
    suppressions: SuppressionStore = field(default_factory=SuppressionStore)
    projectiles: ProjectileStore = field(default_factory=ProjectileStore)
    conditions: OperativeConditionStore = field(default_factory=OperativeConditionStore)
    contacts: ContactStore = field(default_factory=ContactStore)
    messages: MessageLedger = field(default_factory=MessageLedger)
    signals: SignalStore = field(default_factory=SignalStore)
    objectives: ObjectiveStore = field(default_factory=ObjectiveStore)
    scheduled_events: ScheduledEventQueue = field(default_factory=ScheduledEventQueue)
    random_streams: RandomStreams = field(default_factory=default_random_streams)

    def __post_init__(self) -> None:
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("mission tick must be an integer")
        if not 0 <= self.tick <= MAX_MISSION_TICK:
            raise ValueError("mission tick must fit non-negative signed 64-bit range")
        if not isinstance(self.phase, MissionPhase):
            raise ValueError("mission phase must be a MissionPhase")
        if not isinstance(self.entities, tuple):
            raise ValueError("mission entities must be an immutable tuple")
        if self.map_geometry is not None and not isinstance(self.map_geometry, MapGeometry):
            raise ValueError("mission map geometry must be map geometry or absent")
        if not isinstance(self.movement_actions, tuple):
            raise ValueError("mission movement actions must be an immutable tuple")
        if not isinstance(self.id_allocator, IdAllocator):
            raise ValueError("mission state requires an ID allocator")
        if not isinstance(self.policy_memory, PolicyMemoryStore):
            raise ValueError("mission state requires policy memory")
        if not isinstance(self.policy_versions, PolicyVersionStore):
            raise ValueError("mission state requires policy versions")
        if not isinstance(self.covers, CoverStore):
            raise ValueError("mission state requires a cover store")
        if not isinstance(self.cover_reservations, CoverReservationStore):
            raise ValueError("mission state requires a cover reservation store")
        if not isinstance(self.weapons, WeaponStore):
            raise ValueError("mission state requires a weapon store")
        if not isinstance(self.aim_states, AimStore):
            raise ValueError("mission state requires an aim store")
        if not isinstance(self.suppressions, SuppressionStore):
            raise ValueError("mission state requires a suppression store")
        if not isinstance(self.projectiles, ProjectileStore):
            raise ValueError("mission state requires a projectile store")
        if not isinstance(self.conditions, OperativeConditionStore):
            raise ValueError("mission state requires operative conditions")
        if not isinstance(self.contacts, ContactStore):
            raise ValueError("mission state requires a contact store")
        if not isinstance(self.messages, MessageLedger):
            raise ValueError("mission state requires a message ledger")
        if not isinstance(self.signals, SignalStore):
            raise ValueError("mission state requires a signal store")
        if not isinstance(self.objectives, ObjectiveStore):
            raise ValueError("mission state requires an objective store")
        if not isinstance(self.scheduled_events, ScheduledEventQueue):
            raise ValueError("mission state requires a scheduled event queue")
        if not isinstance(self.random_streams, RandomStreams):
            raise ValueError("mission state requires random streams")
        previous_id = 0
        for entity in self.entities:
            if not isinstance(entity, EntityState):
                raise ValueError("mission entities must be entity states")
            if entity.entity_id.value <= previous_id:
                raise ValueError("mission entities must have unique ascending entity IDs")
            previous_id = entity.entity_id.value
        next_entity_id = self.id_allocator.next_ids[int(IdKind.ENTITY)]
        if previous_id >= next_entity_id:
            raise ValueError("mission entity IDs must be allocated by the current ID allocator")
        if self.map_geometry is not None:
            next_obstacle_id = self.id_allocator.next_ids[int(IdKind.OBSTACLE)]
            if self.map_geometry.obstacles and (
                self.map_geometry.obstacles[-1].obstacle_id.value >= next_obstacle_id
            ):
                raise ValueError("map obstacle IDs must be allocated by the current ID allocator")
            if any(
                not self.map_geometry.contains_position(entity.position) for entity in self.entities
            ):
                raise ValueError("mission entity positions must lie within map bounds")
        entity_ids = tuple(entity.entity_id for entity in self.entities)
        next_objective_id = self.id_allocator.next_ids[int(IdKind.OBJECTIVE)]
        if any(
            objective.objective_id.value >= next_objective_id
            for objective in self.objectives.entries
        ):
            raise ValueError("objective IDs must be allocated by the current ID allocator")
        if any(
            required_id not in entity_ids
            for objective in self.objectives.entries
            for required_id in objective.required_entity_ids
        ):
            raise ValueError("objective entities must belong to mission entities")
        if any(
            objective.retrieval_event_id is not None
            and objective.retrieval_event_id.value >= self.id_allocator.next_ids[int(IdKind.EVENT)]
            for objective in self.objectives.entries
        ):
            raise ValueError("objective retrieval event IDs must be allocated")
        previous_movement_entity_id = 0
        next_event_id = self.id_allocator.next_ids[int(IdKind.EVENT)]
        for action in self.movement_actions:
            if not isinstance(action, MovementAction):
                raise ValueError("mission movement actions must be movement actions")
            if action.entity_id.value <= previous_movement_entity_id:
                raise ValueError("mission movement actions must be entity-ID ordered")
            if action.entity_id not in entity_ids:
                raise ValueError("movement actions must belong to mission entities")
            if self.map_geometry is None or action.path.query.map_geometry != self.map_geometry:
                raise ValueError("movement action paths must use mission map geometry")
            entity = next(
                entity for entity in self.entities if entity.entity_id == action.entity_id
            )
            if entity.position != movement_action_position(action):
                raise ValueError("movement action progress must match the entity position")
            if action.origin_event_id is not None and action.origin_event_id.value >= next_event_id:
                raise ValueError("movement action origin event must already be allocated")
            previous_movement_entity_id = action.entity_id.value
        if any(entry.entity_id not in entity_ids for entry in self.policy_memory.entries):
            raise ValueError("policy memory entries must belong to mission entities")
        if any(entry.entity_id not in entity_ids for entry in self.policy_versions.entries):
            raise ValueError("policy version entries must belong to mission entities")
        next_cover_id = self.id_allocator.next_ids[int(IdKind.COVER)]
        if any(segment.cover_id.value >= next_cover_id for segment in self.covers.segments):
            raise ValueError("cover IDs must be allocated by the current ID allocator")
        next_weapon_id = self.id_allocator.next_ids[int(IdKind.WEAPON)]
        if any(weapon.weapon_id.value >= next_weapon_id for weapon in self.weapons.entries):
            raise ValueError("weapon IDs must be allocated by the current ID allocator")
        if any(weapon.owner_entity_id not in entity_ids for weapon in self.weapons.entries):
            raise ValueError("weapons must belong to mission entities")
        if any(aim_state.entity_id not in entity_ids for aim_state in self.aim_states.entries):
            raise ValueError("aim states must belong to mission entities")
        if any(
            suppression.entity_id not in entity_ids for suppression in self.suppressions.entries
        ):
            raise ValueError("suppression states must belong to mission entities")
        next_projectile_id = self.id_allocator.next_ids[int(IdKind.PROJECTILE)]
        if any(
            projectile.projectile_id.value >= next_projectile_id
            for projectile in self.projectiles.entries
        ):
            raise ValueError("projectile IDs must be allocated by the current ID allocator")
        if any(
            projectile.owner_entity_id not in entity_ids for projectile in self.projectiles.entries
        ):
            raise ValueError("projectiles must belong to mission entities")
        next_intention_id = self.id_allocator.next_ids[int(IdKind.INTENTION)]
        if any(
            projectile.source_intention_id.value >= next_intention_id
            for projectile in self.projectiles.entries
        ):
            raise ValueError("projectile source intention IDs must be allocated")
        if any(
            projectile.source_intention.issuer_entity_id != projectile.owner_entity_id
            for projectile in self.projectiles.entries
        ):
            raise ValueError("projectile provenance issuer must match its owner")
        next_invocation_id = self.id_allocator.next_ids[int(IdKind.POLICY_INVOCATION)]
        if any(
            projectile.source_intention.invocation_id.value >= next_invocation_id
            for projectile in self.projectiles.entries
        ):
            raise ValueError("projectile source invocation IDs must be allocated")
        if any(
            projectile.source_intention.creation_tick > self.tick
            for projectile in self.projectiles.entries
        ):
            raise ValueError("projectile source intentions cannot be created after mission state")
        if any(condition.entity_id not in entity_ids for condition in self.conditions.entries):
            raise ValueError("operative conditions must belong to mission entities")
        if any(
            self.conditions.is_incapacitated(action.entity_id) for action in self.movement_actions
        ):
            raise ValueError("incapacitated entities cannot retain movement actions")
        if any(
            self.conditions.is_incapacitated(reservation.entity_id)
            for reservation in self.cover_reservations.entries
        ):
            raise ValueError("incapacitated entities cannot retain cover reservations")
        for reservation in self.cover_reservations.entries:
            if reservation.entity_id not in entity_ids:
                raise ValueError("cover reservations must belong to mission entities")
            segment = self.covers.segment_for(reservation.cover_id)
            if segment is None or segment.slot_for(reservation.slot_index) is None:
                raise ValueError("cover reservations must reference mission cover slots")
        if any(
            reservation.intention_id.value >= next_intention_id
            for reservation in self.cover_reservations.entries
        ):
            raise ValueError(
                "cover reservation intention IDs must be allocated by the current ID allocator"
            )
        if any(estimate.owner_entity_id not in entity_ids for estimate in self.contacts.estimates):
            raise ValueError("contact estimates must belong to mission entities")
        if self.contacts.lifecycle_tick > self.tick:
            raise ValueError("contact lifecycle tick must not exceed the mission tick")
        next_contact_id = self.id_allocator.next_ids[int(IdKind.CONTACT)]
        if any(
            estimate.contact_id.value >= next_contact_id for estimate in self.contacts.estimates
        ):
            raise ValueError("contact IDs must be allocated by the current ID allocator")
        if any(
            event_id.value >= next_event_id
            for estimate in self.contacts.estimates
            for field_provenance in estimate.provenance.fields
            for event_id in field_provenance.evidence_event_ids
        ):
            raise ValueError(
                "contact evidence event IDs must be allocated by the current ID allocator"
            )
        if any(
            message.sender_entity_id not in entity_ids
            or message.recipient_entity_id not in entity_ids
            for message in self.messages.messages
        ):
            raise ValueError("messages must reference mission entities")
        next_message_id = self.id_allocator.next_ids[int(IdKind.MESSAGE)]
        if any(message.message_id.value >= next_message_id for message in self.messages.messages):
            raise ValueError("message IDs must be allocated by the current ID allocator")
        if any(
            event_id.value >= next_event_id
            for message in self.messages.messages
            for event_id in message.provenance_event_ids
        ):
            raise ValueError(
                "message provenance event IDs must be allocated by the current ID allocator"
            )
        if any(message.send_event_id.value >= next_event_id for message in self.messages.messages):
            raise ValueError("message send event IDs must be allocated by the current ID allocator")
        if any(
            signal.tick > self.tick
            or (signal.target_entity_id is not None and signal.target_entity_id not in entity_ids)
            for signal in self.signals.signals
        ):
            raise ValueError("signals must be current or prior and target mission entities")
        if any(
            signal.provenance_event_id.value >= next_event_id for signal in self.signals.signals
        ):
            raise ValueError("signal event IDs must be allocated by the current ID allocator")


def add_entity(state: MissionState, position: WorldPosition) -> tuple[MissionState, EntityState]:
    """Allocate and append one entity in canonical entity-ID order."""
    if not isinstance(state, MissionState):
        raise ValueError("entity creation requires mission state")
    if not isinstance(position, WorldPosition):
        raise ValueError("entity creation requires a world position")
    entity_id, id_allocator = state.id_allocator.allocate_entity()
    entity = EntityState(entity_id=entity_id, position=position)
    return (
        MissionState(
            tick=state.tick,
            phase=state.phase,
            entities=state.entities + (entity,),
            map_geometry=state.map_geometry,
            movement_actions=state.movement_actions,
            id_allocator=id_allocator,
            policy_memory=state.policy_memory,
            policy_versions=state.policy_versions,
            covers=state.covers,
            cover_reservations=state.cover_reservations,
            weapons=state.weapons,
            aim_states=state.aim_states,
            suppressions=state.suppressions,
            projectiles=state.projectiles,
            conditions=state.conditions,
            contacts=state.contacts,
            messages=state.messages,
            signals=state.signals,
            objectives=state.objectives,
            scheduled_events=state.scheduled_events,
            random_streams=state.random_streams,
        ),
        entity,
    )
