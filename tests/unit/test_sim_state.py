from __future__ import annotations

import pytest

from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import CoverId, EntityId, EventId, IdAllocator
from kiwi.sim.contacts import (
    ContactConfidence,
    ContactEstimate,
    ContactField,
    ContactFieldProvenance,
    ContactProvenance,
    ContactStore,
)
from kiwi.sim.covers import (
    CoverHeight,
    CoverIntegrity,
    CoverReservation,
    CoverReservationStore,
    CoverSegment,
    CoverSide,
    CoverSlot,
    CoverStore,
)
from kiwi.sim.map_geometry import MapGeometry, MapObstacle
from kiwi.sim.randomness import default_random_streams
from kiwi.sim.scheduled import ScheduledEventQueue
from kiwi.sim.state import MAX_MISSION_TICK, EntityState, MissionPhase, MissionState, add_entity


def position(x: int = 0, y: int = 0) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))


def rectangle(minimum_x: int, minimum_y: int, maximum_x: int, maximum_y: int) -> WorldRectangle:
    return WorldRectangle(
        WorldSubunits(minimum_x),
        WorldSubunits(minimum_y),
        WorldSubunits(maximum_x),
        WorldSubunits(maximum_y),
    )


def test_mission_state_defaults_to_empty_tick_zero_authority() -> None:
    assert MissionState() == MissionState(
        tick=0,
        phase=MissionPhase.PREPARED,
        entities=(),
        id_allocator=IdAllocator(),
        scheduled_events=ScheduledEventQueue(),
        random_streams=default_random_streams(),
    )


def test_add_entity_preserves_prior_state_and_canonical_id_order() -> None:
    initial = MissionState(tick=7)
    after_first, first = add_entity(initial, position(10, -20))
    after_second, second = add_entity(after_first, position(30, 40))

    assert initial.entities == ()
    assert first == EntityState(EntityId(1), position(10, -20))
    assert second == EntityState(EntityId(2), position(30, 40))
    assert after_second.tick == 7
    assert after_second.entities == (first, second)
    assert after_second.id_allocator.next_ids[0] == 3


def test_mission_state_validates_map_provenance_and_entity_bounds() -> None:
    obstacle_id, allocator = IdAllocator().allocate_obstacle()
    geometry = MapGeometry(
        rectangle(-100, -100, 100, 100),
        (MapObstacle(obstacle_id, rectangle(-50, -50, 50, 50)),),
    )
    state = MissionState(map_geometry=geometry, id_allocator=allocator)
    with_entity, _ = add_entity(state, position(100, -100))

    assert with_entity.map_geometry == geometry
    with pytest.raises(ValueError, match="allocated by"):
        MissionState(map_geometry=geometry)
    with pytest.raises(ValueError, match="within map bounds"):
        add_entity(state, position(101, 0))


def test_mission_state_validates_entity_order_and_allocator_provenance() -> None:
    first_id, after_first = IdAllocator().allocate_entity()
    second_id, after_second = after_first.allocate_entity()
    first = EntityState(first_id, position())
    second = EntityState(second_id, position(1))

    with pytest.raises(ValueError, match="unique ascending"):
        MissionState(entities=(second, first), id_allocator=after_second)
    with pytest.raises(ValueError, match="allocated by"):
        MissionState(entities=(first,), id_allocator=IdAllocator())


def test_mission_state_rejects_contact_evidence_without_an_allocated_event() -> None:
    entity_id, allocator = IdAllocator().allocate_entity()
    contact_id, allocator = allocator.allocate_contact()
    estimate = ContactEstimate(
        contact_id,
        entity_id,
        position(),
        WorldSubunits(0),
        ContactConfidence(100),
        0,
        ContactProvenance(
            tuple(ContactFieldProvenance(field, (EventId(1),)) for field in ContactField)
        ),
    )

    with pytest.raises(ValueError, match="contact evidence event IDs"):
        MissionState(
            entities=(EntityState(entity_id, position()),),
            id_allocator=allocator,
            contacts=ContactStore((estimate,)),
        )


def test_mission_state_rejects_cover_ids_without_allocator_provenance() -> None:
    cover = CoverSegment(
        CoverId(1),
        position(0, 0),
        position(1_000, 0),
        CoverHeight.LOW,
        CoverIntegrity(10_000),
        (CoverSlot(0, position(0, -350), CoverSide.LEFT),),
    )

    with pytest.raises(ValueError, match="cover IDs must be allocated"):
        MissionState(covers=CoverStore((cover,)))


def test_mission_state_rejects_cover_reservations_without_valid_authority_references() -> None:
    cover_id, allocator = IdAllocator().allocate_cover()
    intention_id, allocator = allocator.allocate_intention()
    cover = CoverSegment(
        cover_id,
        position(0, 0),
        position(1_000, 0),
        CoverHeight.LOW,
        CoverIntegrity(10_000),
        (CoverSlot(0, position(0, -350), CoverSide.LEFT),),
    )
    reservations = CoverReservationStore(
        (CoverReservation(cover_id, 0, EntityId(1), intention_id),)
    )

    with pytest.raises(ValueError, match="belong to mission entities"):
        MissionState(
            covers=CoverStore((cover,)),
            cover_reservations=reservations,
            id_allocator=allocator,
        )


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: MissionState(tick=-1), "non-negative"),
        (lambda: MissionState(tick=MAX_MISSION_TICK + 1), "signed 64-bit"),
        (lambda: MissionState(tick=True), "integer"),
        (lambda: MissionState(phase="prepared"), "MissionPhase"),  # type: ignore[arg-type]
        (lambda: MissionState(entities=[]), "immutable tuple"),  # type: ignore[arg-type]
        (lambda: MissionState(map_geometry=object()), "map geometry"),  # type: ignore[arg-type]
        (lambda: EntityState(EntityId(1), position=object()), "world position"),  # type: ignore[arg-type]
        (lambda: add_entity(MissionState(), object()), "world position"),  # type: ignore[arg-type]
    ),
)
def test_mission_state_rejects_invalid_canonical_values(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]
