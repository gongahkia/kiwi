from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
from kiwi.dsl.runtime_values import RecordValue, StringValue
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.determinism import (
    compare_headless_runs,
    first_canonical_state_difference,
    run_determinism_harness,
)
from kiwi.sim.map_geometry import MapGeometry
from kiwi.sim.memory import PolicyMemoryStore
from kiwi.sim.pathing import Path, PathQuery
from kiwi.sim.runner import HeadlessRun, run_headless
from kiwi.sim.snapshot import capture_authority_snapshot
from kiwi.sim.state import MissionPhase, MissionState, MovementAction, add_entity


def test_determinism_harness_repeats_checkpoint_hashes_exactly() -> None:
    report = run_determinism_harness(
        MissionState(),
        FixedTickClock(TickRate.HZ_30),
        3,
        checkpoint_interval=2,
    )

    assert report.matches
    assert report.divergence is None
    assert tuple(snapshot.tick for snapshot in report.expected.checkpoints) == (0, 2, 3)
    assert report.expected.checkpoints == report.actual.checkpoints


def test_differential_report_uses_first_canonical_entity_path() -> None:
    expected, _ = add_entity(
        MissionState(),
        WorldPosition(WorldSubunits(1_000), WorldSubunits(2_000)),
    )
    actual = replace(
        expected,
        entities=(
            replace(
                expected.entities[0],
                position=WorldPosition(WorldSubunits(1_001), WorldSubunits(2_000)),
            ),
        ),
    )

    difference = first_canonical_state_difference(expected, actual)

    assert difference is not None
    assert difference.path == "entities/0/position/x"
    assert difference.expected == "1000"
    assert difference.actual == "1001"


def test_differential_report_includes_policy_memory_in_canonical_order() -> None:
    expected, entity = add_entity(
        MissionState(), WorldPosition(WorldSubunits(1_000), WorldSubunits(2_000))
    )
    actual = replace(
        expected,
        policy_memory=PolicyMemoryStore().with_memory(
            entity.entity_id,
            RecordValue("Memory", ("label",), (StringValue("ready"),)),
        ),
    )

    difference = first_canonical_state_difference(expected, actual)

    assert difference is not None
    assert difference.path == "policy_memory/count"
    assert difference.expected == "0"
    assert difference.actual == "1"


def test_differential_report_includes_map_geometry_in_canonical_order() -> None:
    expected = MissionState(
        map_geometry=MapGeometry(
            WorldRectangle(WorldSubunits(0), WorldSubunits(0), WorldSubunits(10), WorldSubunits(10))
        )
    )
    actual = replace(
        expected,
        map_geometry=MapGeometry(
            WorldRectangle(WorldSubunits(1), WorldSubunits(0), WorldSubunits(10), WorldSubunits(10))
        ),
    )

    difference = first_canonical_state_difference(expected, actual)

    assert difference is not None
    assert difference.path == "map_geometry/bounds/minimum_x"
    assert difference.expected == "0"
    assert difference.actual == "1"


def test_differential_report_includes_future_movement_waypoints() -> None:
    geometry = MapGeometry(
        WorldRectangle(
            WorldSubunits(-1_000), WorldSubunits(-1_000), WorldSubunits(1_000), WorldSubunits(1_000)
        )
    )
    start = WorldPosition(WorldSubunits(0), WorldSubunits(0))
    expected, entity = add_entity(MissionState(map_geometry=geometry), start)
    expected_path = Path(
        PathQuery(geometry, start, WorldPosition(WorldSubunits(100), WorldSubunits(200))),
        (
            start,
            WorldPosition(WorldSubunits(100), WorldSubunits(0)),
            WorldPosition(WorldSubunits(100), WorldSubunits(200)),
        ),
    )
    actual_path = Path(
        PathQuery(geometry, start, WorldPosition(WorldSubunits(200), WorldSubunits(200))),
        (
            start,
            WorldPosition(WorldSubunits(100), WorldSubunits(0)),
            WorldPosition(WorldSubunits(200), WorldSubunits(200)),
        ),
    )
    expected = replace(
        expected, movement_actions=(MovementAction(entity.entity_id, expected_path),)
    )
    actual = replace(expected, movement_actions=(MovementAction(entity.entity_id, actual_path),))

    difference = first_canonical_state_difference(expected, actual)

    assert difference is not None
    assert difference.path == "movement_actions/0/waypoints/2/x"
    assert difference.expected == "100"
    assert difference.actual == "200"


def test_run_comparison_reports_first_divergent_checkpoint() -> None:
    expected_state = MissionState(tick=1)
    actual_state = replace(expected_state, phase=MissionPhase.ACTIVE)
    expected = HeadlessRun(
        expected_state,
        (),
        (capture_authority_snapshot(expected_state),),
    )
    actual = HeadlessRun(
        actual_state,
        (),
        (capture_authority_snapshot(actual_state),),
    )

    divergence = compare_headless_runs(expected, actual)

    assert divergence is not None
    assert divergence.tick == 1
    assert divergence.difference.path == "phase"
    assert divergence.expected_hash != divergence.actual_hash


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (
            lambda: run_headless(
                MissionState(),
                FixedTickClock(TickRate.HZ_30),
                1,
                checkpoint_interval=0,
            ),
            "positive integer",
        ),
        (
            lambda: first_canonical_state_difference(object(), MissionState()),  # type: ignore[arg-type]
            "mission states",
        ),
    ),
)
def test_determinism_helpers_reject_invalid_inputs(factory: object, message: str) -> None:
    with pytest.raises((TypeError, ValueError), match=message):
        factory()  # type: ignore[operator]
