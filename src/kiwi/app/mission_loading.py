"""Headless application adapter from validated mission content to authority state."""

from __future__ import annotations

from kiwi.content.missions import MissionData
from kiwi.domain.ids import IdAllocator
from kiwi.sim.covers import (
    CoverHeight,
    CoverIntegrity,
    CoverSegment,
    CoverSide,
    CoverSlot,
    CoverStore,
)
from kiwi.sim.map_geometry import MapGeometry, MapObstacle
from kiwi.sim.randomness import MissionSeed, RandomStreams
from kiwi.sim.state import MissionState


def materialise_mission_state(mission: MissionData) -> MissionState:
    """Allocate map and cover IDs in canonical content order for one mission."""
    if not isinstance(mission, MissionData):
        raise TypeError("mission state materialisation requires mission data")
    geometry, allocator = _materialise_geometry(mission)
    covers, allocator = _materialise_covers(mission, allocator)
    return MissionState(
        map_geometry=geometry,
        covers=covers,
        id_allocator=allocator,
        random_streams=RandomStreams.from_seed(MissionSeed(mission.seed)),
    )


def _materialise_geometry(mission: MissionData) -> tuple[MapGeometry, IdAllocator]:
    allocator = IdAllocator()
    obstacles: list[MapObstacle] = []
    for obstacle in mission.obstacles:
        obstacle_id, allocator = allocator.allocate_obstacle()
        obstacles.append(MapObstacle(obstacle_id, obstacle.bounds, obstacle.elevation))
    return MapGeometry(mission.map_bounds, tuple(obstacles)), allocator


def _materialise_covers(
    mission: MissionData, allocator: IdAllocator
) -> tuple[CoverStore, IdAllocator]:
    covers: list[CoverSegment] = []
    for cover in mission.covers:
        cover_id, allocator = allocator.allocate_cover()
        covers.append(
            CoverSegment(
                cover_id,
                cover.start,
                cover.end,
                CoverHeight(cover.height.value),
                CoverIntegrity(cover.integrity_basis_points),
                tuple(
                    CoverSlot(index, slot.position, CoverSide(slot.side.value))
                    for index, slot in enumerate(cover.slots)
                ),
            )
        )
    return CoverStore(tuple(covers)), allocator
