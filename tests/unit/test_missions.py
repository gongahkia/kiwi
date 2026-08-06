from __future__ import annotations

import json
from pathlib import Path

import pytest

from kiwi.app.mission_loading import materialise_mission_state
from kiwi.content.missions import (
    MissionData,
    MissionDiagnosticCode,
    MissionLoadFailure,
    load_mission_bytes,
    load_mission_file,
)
from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.pathing import Path as TacticalPath
from kiwi.sim.pathing import PathQuery, find_path

MISSION_PATH = (
    Path(__file__).resolve().parents[2] / "examples" / "missions" / "terminal.dmission.json"
)


def _region_centre(mission: MissionData, content_id: str) -> WorldPosition:
    region = mission.region_for(content_id)
    assert region is not None
    bounds = region.bounds
    return WorldPosition(
        WorldSubunits((bounds.minimum_x.value + bounds.maximum_x.value) // 2),
        WorldSubunits((bounds.minimum_y.value + bounds.maximum_y.value) // 2),
    )


def test_terminal_mission_materialises_canonical_geometry_and_cover() -> None:
    mission = load_mission_file(MISSION_PATH)

    assert isinstance(mission, MissionData)
    first = materialise_mission_state(mission)
    second = materialise_mission_state(mission)

    assert mission.mission_id == "terminal"
    assert mission.tick_rate == 30
    assert tuple(obstacle.content_id for obstacle in mission.obstacles) == tuple(
        sorted(obstacle.content_id for obstacle in mission.obstacles)
    )
    assert tuple(cover.content_id for cover in mission.covers) == tuple(
        sorted(cover.content_id for cover in mission.covers)
    )
    assert first == second
    assert hash_canonical_state(first) == hash_canonical_state(second)
    assert first.map_geometry is not None
    assert len(first.map_geometry.obstacles) == 10
    assert len(first.covers.segments) == 6
    assert first.random_streams.seed.value == mission.seed


def test_terminal_has_two_clear_approaches_to_the_objective_room() -> None:
    mission = load_mission_file(MISSION_PATH)

    assert isinstance(mission, MissionData)
    state = materialise_mission_state(mission)
    assert state.map_geometry is not None
    goal = _region_centre(mission, "objective_room")

    for entrance in ("west_entrance", "east_entrance"):
        start = _region_centre(mission, entrance)
        result = find_path(PathQuery(state.map_geometry, start, goal))
        assert isinstance(result, TacticalPath)
        assert result.waypoints[0] == start
        assert result.waypoints[-1] == goal


def test_mission_array_order_cannot_change_materialised_authority() -> None:
    first = load_mission_file(MISSION_PATH)
    document = json.loads(MISSION_PATH.read_text(encoding="utf-8"))
    document["map"]["obstacles"].reverse()
    document["covers"].reverse()
    document["regions"].reverse()
    for cover in document["covers"]:
        cover["slots"].reverse()
    second = load_mission_bytes(json.dumps(document).encode("utf-8"))

    assert isinstance(first, MissionData)
    assert isinstance(second, MissionData)
    assert first == second
    assert materialise_mission_state(first) == materialise_mission_state(second)


@pytest.mark.parametrize(
    ("data", "code", "path"),
    (
        (b"\xff", MissionDiagnosticCode.INVALID_UTF8, "$"),
        (b"{", MissionDiagnosticCode.INVALID_JSON, "$"),
        (
            b'{"format":"kiwi-mission","version":1,"id":"bad","title":"Bad","tick_rate":30,"seed":0,"map":{"bounds":{"minimum_x":0,"minimum_y":0,"maximum_x":1,"maximum_y":1},"obstacles":[]},"covers":[],"regions":[],"extra":0}',
            MissionDiagnosticCode.UNKNOWN_FIELD,
            "$",
        ),
        (
            b'{"format":"kiwi-mission","version":2,"id":"bad","title":"Bad","tick_rate":30,"seed":0,"map":{"bounds":{"minimum_x":0,"minimum_y":0,"maximum_x":1,"maximum_y":1},"obstacles":[]},"covers":[],"regions":[]}',
            MissionDiagnosticCode.UNSUPPORTED_VERSION,
            "$.version",
        ),
        (
            b'{"format":"kiwi-mission","version":1,"id":"bad","title":"Bad","tick_rate":30,"seed":0,"map":{"bounds":{"minimum_x":0,"minimum_y":0,"maximum_x":1,"maximum_y":1},"obstacles":[]},"covers":[],"regions":[{"id":"outside","bounds":{"minimum_x":0,"minimum_y":0,"maximum_x":2,"maximum_y":1}}]}',
            MissionDiagnosticCode.INVALID_VALUE,
            "$",
        ),
    ),
)
def test_mission_loader_returns_structured_failures(
    data: bytes, code: MissionDiagnosticCode, path: str
) -> None:
    result = load_mission_bytes(data, "mission.json")

    assert isinstance(result, MissionLoadFailure)
    assert result.source == "mission.json"
    assert result.diagnostics[0].code is code
    assert result.diagnostics[0].path == path


def test_mission_loader_rejects_duplicate_json_fields() -> None:
    result = load_mission_bytes(b'{"format":"kiwi-mission","format":"kiwi-mission"}')

    assert isinstance(result, MissionLoadFailure)
    assert result.diagnostics[0].code is MissionDiagnosticCode.DUPLICATE_FIELD
