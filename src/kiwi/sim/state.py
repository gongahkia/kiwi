"""Minimal immutable authoritative mission state."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from kiwi.domain.geometry import WorldPosition
from kiwi.domain.ids import EntityId, IdAllocator, IdKind
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.memory import PolicyMemoryStore
from kiwi.sim.randomness import RandomStreams, default_random_streams
from kiwi.sim.scheduled import ScheduledEventQueue

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
class MissionState:
    """The canonical state fields defined by the initial simulation kernel."""

    tick: int = 0
    phase: MissionPhase = MissionPhase.PREPARED
    entities: tuple[EntityState, ...] = ()
    id_allocator: IdAllocator = field(default_factory=IdAllocator)
    policy_memory: PolicyMemoryStore = field(default_factory=PolicyMemoryStore)
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
        if not isinstance(self.id_allocator, IdAllocator):
            raise ValueError("mission state requires an ID allocator")
        if not isinstance(self.policy_memory, PolicyMemoryStore):
            raise ValueError("mission state requires policy memory")
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
        entity_ids = tuple(entity.entity_id for entity in self.entities)
        if any(entry.entity_id not in entity_ids for entry in self.policy_memory.entries):
            raise ValueError("policy memory entries must belong to mission entities")


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
            id_allocator=id_allocator,
            policy_memory=state.policy_memory,
            scheduled_events=state.scheduled_events,
            random_streams=state.random_streams,
        ),
        entity,
    )
