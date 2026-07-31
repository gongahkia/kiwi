"""Minimal immutable authoritative mission state."""

from __future__ import annotations

from dataclasses import dataclass, field

from kiwi.domain.geometry import WorldPosition
from kiwi.domain.ids import EntityId, IdAllocator, IdKind

MAX_MISSION_TICK = (1 << 63) - 1


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
    entities: tuple[EntityState, ...] = ()
    id_allocator: IdAllocator = field(default_factory=IdAllocator)

    def __post_init__(self) -> None:
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("mission tick must be an integer")
        if not 0 <= self.tick <= MAX_MISSION_TICK:
            raise ValueError("mission tick must fit non-negative signed 64-bit range")
        if not isinstance(self.id_allocator, IdAllocator):
            raise ValueError("mission state requires an ID allocator")
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
            entities=state.entities + (entity,),
            id_allocator=id_allocator,
        ),
        entity,
    )
