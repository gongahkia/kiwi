"""Immutable bounded obstacle geometry for authoritative tactical maps."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldRectangle
from kiwi.domain.ids import ObstacleId


@dataclass(frozen=True, slots=True)
class MapObstacle:
    """One closed axis-aligned obstacle at a discrete elevation layer."""

    obstacle_id: ObstacleId
    bounds: WorldRectangle
    elevation: ElevationLayer = ElevationLayer()

    def __post_init__(self) -> None:
        if not isinstance(self.obstacle_id, ObstacleId):
            raise ValueError("map obstacle requires an obstacle ID")
        if not isinstance(self.bounds, WorldRectangle):
            raise ValueError("map obstacle requires world rectangle bounds")
        if not isinstance(self.elevation, ElevationLayer):
            raise ValueError("map obstacle requires an elevation layer")


@dataclass(frozen=True, slots=True)
class MapGeometry:
    """One bounded planar map and its obstacle-ID-ordered closed obstacles."""

    bounds: WorldRectangle
    obstacles: tuple[MapObstacle, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.bounds, WorldRectangle):
            raise ValueError("map geometry requires world rectangle bounds")
        if not isinstance(self.obstacles, tuple):
            raise ValueError("map obstacles must be an immutable tuple")
        previous_id = 0
        for obstacle in self.obstacles:
            if not isinstance(obstacle, MapObstacle):
                raise ValueError("map obstacles must be map obstacles")
            if obstacle.obstacle_id.value <= previous_id:
                raise ValueError("map obstacles must have unique ascending obstacle IDs")
            if not self.bounds.contains_rectangle(obstacle.bounds):
                raise ValueError("map obstacle bounds must lie within map bounds")
            previous_id = obstacle.obstacle_id.value

    def contains_position(self, position: WorldPosition) -> bool:
        """Return whether a position lies within the closed planar map boundary."""
        return self.bounds.contains_position(position)
