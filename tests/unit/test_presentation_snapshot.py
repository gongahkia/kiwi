from __future__ import annotations

from dataclasses import fields, replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import EventId, IdAllocator
from kiwi.sim.contacts import (
    ContactConfidence,
    ContactField,
    ContactFieldProvenance,
    ContactProvenance,
    ContactSighting,
    apply_contact_sightings,
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
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.map_geometry import MapGeometry, MapObstacle
from kiwi.sim.pathing import Path, PathQuery, prepare_path_query
from kiwi.sim.snapshot import (
    PresentationContact,
    PresentationCover,
    PresentationCoverSlot,
    PresentationMap,
    PresentationObstacle,
    PresentationOperative,
    PresentationPoint,
    PresentationRectangle,
    PresentationSnapshot,
    PresentationVisibilityOverlay,
    PresentationVisibleObstacle,
    build_presentation_snapshot,
    build_presentation_visibility_overlay,
)
from kiwi.sim.state import MissionPhase, MissionState, MovementAction, add_entity
from kiwi.sim.visibility import SensorRange, VisibleGeometry, visible_geometry


def position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))


def rectangle(minimum_x: int, minimum_y: int, maximum_x: int, maximum_y: int) -> WorldRectangle:
    return WorldRectangle(
        WorldSubunits(minimum_x),
        WorldSubunits(minimum_y),
        WorldSubunits(maximum_x),
        WorldSubunits(maximum_y),
    )


def test_presentation_snapshot_copies_display_values_without_mutating_authority() -> None:
    obstacle_id, allocator = IdAllocator().allocate_obstacle()
    geometry = MapGeometry(
        rectangle(-5_000, -4_000, 5_000, 4_000),
        (MapObstacle(obstacle_id, rectangle(-500, -200, 500, 200)),),
    )
    state, first = add_entity(
        MissionState(map_geometry=geometry, id_allocator=allocator), position(-2_000, 0)
    )
    state, second = add_entity(state, position(1_000, 1_500))
    cover_id, allocator = state.id_allocator.allocate_cover()
    intention_id, allocator = allocator.allocate_intention()
    state = replace(
        state,
        id_allocator=allocator,
        covers=CoverStore(
            (
                CoverSegment(
                    cover_id,
                    position(-1_000, 500),
                    position(2_000, 500),
                    CoverHeight.HIGH,
                    CoverIntegrity(7_500),
                    (
                        CoverSlot(0, first.position, CoverSide.LEFT),
                        CoverSlot(1, second.position, CoverSide.RIGHT),
                        CoverSlot(2, position(0, -1_000), CoverSide.LEFT),
                    ),
                ),
            )
        ),
        cover_reservations=CoverReservationStore(
            (CoverReservation(cover_id, 2, first.entity_id, intention_id),)
        ),
    )
    query = prepare_path_query(geometry, first.position, position(2_000, 0))
    assert isinstance(query, PathQuery)
    path = Path(query, (first.position, position(-1_000, 0), position(2_000, 0)))
    state = replace(
        state,
        phase=MissionPhase.ACTIVE,
        movement_actions=(MovementAction(first.entity_id, path),),
    )
    state_hash = hash_canonical_state(state)

    snapshot = build_presentation_snapshot(state)

    assert hash_canonical_state(state) == state_hash
    assert tuple(field.name for field in fields(PresentationSnapshot)) == (
        "tick",
        "phase",
        "map_geometry",
        "operatives",
        "objective_marker",
        "contacts",
        "visibility_overlays",
        "covers",
    )
    assert snapshot == PresentationSnapshot(
        tick=0,
        phase="active",
        map_geometry=PresentationMap(
            PresentationRectangle(-5_000.0, -4_000.0, 5_000.0, 4_000.0),
            (
                PresentationObstacle(
                    1,
                    PresentationRectangle(-500.0, -200.0, 500.0, 200.0),
                    0,
                ),
            ),
        ),
        operatives=(
            PresentationOperative(
                1,
                PresentationPoint(-2_000.0, 0.0, 0),
                (
                    PresentationPoint(-2_000.0, 0.0, 0),
                    PresentationPoint(-1_000.0, 0.0, 0),
                    PresentationPoint(2_000.0, 0.0, 0),
                ),
            ),
            PresentationOperative(2, PresentationPoint(1_000.0, 1_500.0, 0)),
        ),
        covers=(
            PresentationCover(
                1,
                PresentationPoint(-1_000.0, 500.0, 0),
                PresentationPoint(2_000.0, 500.0, 0),
                "high",
                7_500,
                (
                    PresentationCoverSlot(0, PresentationPoint(-2_000.0, 0.0, 0), "left", 1),
                    PresentationCoverSlot(1, PresentationPoint(1_000.0, 1_500.0, 0), "right", 2),
                    PresentationCoverSlot(2, PresentationPoint(0.0, -1_000.0, 0), "left"),
                ),
            ),
        ),
    )
    assert snapshot.operatives[0].path
    assert snapshot.operatives[1].path == ()
    assert snapshot.map_geometry is not None
    assert snapshot.map_geometry.obstacles[0].obstacle_id == obstacle_id.value
    assert second.entity_id.value == 2
    assert snapshot.covers[0].slots[2].occupant_entity_id is None


@pytest.mark.parametrize(
    "value",
    (
        lambda: PresentationSnapshot(0, "active", None, []),  # type: ignore[arg-type]
        lambda: PresentationSnapshot(0, "", None, ()),
        lambda: PresentationSnapshot(0, "active", None, (), object()),  # type: ignore[arg-type]
        lambda: PresentationOperative(1, PresentationPoint(0.0, 0.0, 0), []),  # type: ignore[arg-type]
        lambda: PresentationRectangle(0.0, 0.0, 0.0, 1.0),
    ),
)
def test_presentation_values_reject_mutable_or_invalid_inputs(value: object) -> None:
    with pytest.raises(ValueError):
        value()  # type: ignore[operator]


def test_presentation_snapshot_requires_authority_state() -> None:
    with pytest.raises(TypeError, match="mission state"):
        build_presentation_snapshot(object())  # type: ignore[arg-type]


def test_presentation_snapshot_copies_contacts_and_visibility_without_authority_references() -> (
    None
):
    obstacle_id, allocator = IdAllocator().allocate_obstacle()
    geometry = MapGeometry(
        rectangle(-2_000, -2_000, 2_000, 2_000),
        (MapObstacle(obstacle_id, rectangle(500, -100, 700, 100)),),
    )
    state, owner = add_entity(
        MissionState(map_geometry=geometry, id_allocator=allocator), position(0, 0)
    )
    evidence_event_id, allocator = state.id_allocator.allocate_event()
    contacts, allocator = apply_contact_sightings(
        state.contacts,
        allocator,
        0,
        (
            ContactSighting(
                owner.entity_id,
                position(1_000, 500),
                WorldSubunits(300),
                ContactConfidence(8_500),
                _contact_provenance(evidence_event_id),
            ),
        ),
    )
    state = replace(state, contacts=contacts, id_allocator=allocator)
    visible = visible_geometry(geometry, owner.position, SensorRange(WorldSubunits(1_000)))
    assert isinstance(visible, VisibleGeometry)
    state_hash = hash_canonical_state(state)

    overlay = build_presentation_visibility_overlay(owner.entity_id, visible)
    snapshot = build_presentation_snapshot(state, (overlay,))

    assert hash_canonical_state(state) == state_hash
    assert snapshot.contacts == (
        PresentationContact(1, 1, PresentationPoint(1_000.0, 500.0, 0), 300.0, 8_500, 0),
    )
    assert snapshot.visibility_overlays == (
        PresentationVisibilityOverlay(
            1,
            PresentationPoint(0.0, 0.0, 0),
            1_000.0,
            (PresentationVisibleObstacle(1, PresentationRectangle(500.0, -100.0, 700.0, 100.0)),),
        ),
    )


def _contact_provenance(event_id: EventId) -> ContactProvenance:
    return ContactProvenance(
        tuple(ContactFieldProvenance(field, (event_id,)) for field in ContactField)
    )
