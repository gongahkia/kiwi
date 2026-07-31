from __future__ import annotations

from dataclasses import fields, replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import IdAllocator
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.map_geometry import MapGeometry, MapObstacle
from kiwi.sim.pathing import Path, PathQuery, prepare_path_query
from kiwi.sim.snapshot import (
    PresentationMap,
    PresentationObstacle,
    PresentationOperative,
    PresentationPoint,
    PresentationRectangle,
    PresentationSnapshot,
    build_presentation_snapshot,
)
from kiwi.sim.state import MissionPhase, MissionState, MovementAction, add_entity


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
    )
    assert snapshot.operatives[0].path
    assert snapshot.operatives[1].path == ()
    assert snapshot.map_geometry is not None
    assert snapshot.map_geometry.obstacles[0].obstacle_id == obstacle_id.value
    assert second.entity_id.value == 2


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
