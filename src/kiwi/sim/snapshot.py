"""Immutable authority checkpoints and non-canonical presentation read models."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.geometry import WorldPosition, WorldRectangle
from kiwi.sim.hashing import (
    StateDecodeFailure,
    StateHash,
    decode_canonical_state,
    encode_canonical_state,
    hash_canonical_state_bytes,
)
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.map_geometry import MapGeometry
from kiwi.sim.state import MissionState


class SnapshotRestoreCode(StrEnum):
    """Stable failures returned while restoring an authority snapshot."""

    INVALID_PAYLOAD = "SS001_INVALID_PAYLOAD"
    TICK_MISMATCH = "SS002_TICK_MISMATCH"
    HASH_MISMATCH = "SS003_HASH_MISMATCH"


@dataclass(frozen=True, slots=True)
class AuthoritySnapshot:
    """A self-verifying authority payload suitable for replay checkpoint storage."""

    tick: int
    canonical_state: bytes
    state_hash: StateHash

    def __post_init__(self) -> None:
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("snapshot tick must be an integer")
        if not 0 <= self.tick <= MAX_AUTHORITY_TICK:
            raise ValueError("snapshot tick must fit non-negative signed 64-bit range")
        if not isinstance(self.canonical_state, bytes):
            raise ValueError("snapshot canonical state must be bytes")
        if not isinstance(self.state_hash, StateHash):
            raise ValueError("snapshot state hash must be a StateHash")


@dataclass(frozen=True, slots=True)
class SnapshotRestoreFailure:
    """One structured authority-snapshot restoration failure."""

    code: SnapshotRestoreCode
    message: str
    state_failure: StateDecodeFailure | None = None


type SnapshotRestoreResult = MissionState | SnapshotRestoreFailure


@dataclass(frozen=True, slots=True)
class PresentationPoint:
    """One display-space world point copied from integer authority coordinates."""

    x: float
    y: float
    elevation: int

    def __post_init__(self) -> None:
        if not isinstance(self.x, float) or not isinstance(self.y, float):
            raise ValueError("presentation point coordinates must be floats")
        if not isinstance(self.elevation, int) or isinstance(self.elevation, bool):
            raise ValueError("presentation point elevation must be an integer")
        if self.elevation < 0:
            raise ValueError("presentation point elevation must be non-negative")


@dataclass(frozen=True, slots=True)
class PresentationRectangle:
    """One display-space closed axis-aligned rectangle."""

    minimum_x: float
    minimum_y: float
    maximum_x: float
    maximum_y: float

    def __post_init__(self) -> None:
        coordinates = (self.minimum_x, self.minimum_y, self.maximum_x, self.maximum_y)
        if not all(isinstance(value, float) for value in coordinates):
            raise ValueError("presentation rectangle coordinates must be floats")
        if self.minimum_x >= self.maximum_x:
            raise ValueError("presentation rectangle x bounds must be ascending")
        if self.minimum_y >= self.maximum_y:
            raise ValueError("presentation rectangle y bounds must be ascending")


@dataclass(frozen=True, slots=True)
class PresentationObstacle:
    """One display-safe static obstacle value."""

    obstacle_id: int
    bounds: PresentationRectangle
    elevation: int

    def __post_init__(self) -> None:
        if not isinstance(self.obstacle_id, int) or isinstance(self.obstacle_id, bool):
            raise ValueError("presentation obstacle ID must be an integer")
        if self.obstacle_id <= 0:
            raise ValueError("presentation obstacle ID must be positive")
        if not isinstance(self.bounds, PresentationRectangle):
            raise ValueError("presentation obstacle bounds must be a presentation rectangle")
        if not isinstance(self.elevation, int) or isinstance(self.elevation, bool):
            raise ValueError("presentation obstacle elevation must be an integer")
        if self.elevation < 0:
            raise ValueError("presentation obstacle elevation must be non-negative")


@dataclass(frozen=True, slots=True)
class PresentationMap:
    """One display-safe map bounds and obstacle tuple."""

    bounds: PresentationRectangle
    obstacles: tuple[PresentationObstacle, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.bounds, PresentationRectangle):
            raise ValueError("presentation map bounds must be a presentation rectangle")
        if not isinstance(self.obstacles, tuple):
            raise ValueError("presentation map obstacles must be an immutable tuple")
        previous_obstacle_id = 0
        for obstacle in self.obstacles:
            if not isinstance(obstacle, PresentationObstacle):
                raise ValueError("presentation map obstacles must be presentation obstacles")
            if obstacle.obstacle_id <= previous_obstacle_id:
                raise ValueError("presentation map obstacles must be ID ordered")
            previous_obstacle_id = obstacle.obstacle_id


@dataclass(frozen=True, slots=True)
class PresentationOperative:
    """One display-safe operative position and current planned path."""

    entity_id: int
    position: PresentationPoint
    path: tuple[PresentationPoint, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.entity_id, int) or isinstance(self.entity_id, bool):
            raise ValueError("presentation operative ID must be an integer")
        if self.entity_id <= 0:
            raise ValueError("presentation operative ID must be positive")
        if not isinstance(self.position, PresentationPoint):
            raise ValueError("presentation operative position must be a presentation point")
        if not isinstance(self.path, tuple):
            raise ValueError("presentation operative path must be an immutable tuple")
        if any(not isinstance(point, PresentationPoint) for point in self.path):
            raise ValueError("presentation operative path must contain presentation points")


@dataclass(frozen=True, slots=True)
class PresentationSnapshot:
    """A non-canonical, display-ready projection with no authority-state reference."""

    tick: int
    phase: str
    map_geometry: PresentationMap | None
    operatives: tuple[PresentationOperative, ...]
    objective_marker: PresentationPoint | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("presentation snapshot tick must be an integer")
        if not 0 <= self.tick <= MAX_AUTHORITY_TICK:
            raise ValueError("presentation snapshot tick must fit non-negative signed 64-bit range")
        if not isinstance(self.phase, str) or not self.phase:
            raise ValueError("presentation snapshot phase must be a non-empty string")
        if self.map_geometry is not None and not isinstance(self.map_geometry, PresentationMap):
            raise ValueError(
                "presentation snapshot map geometry must be presentation map or absent"
            )
        if not isinstance(self.operatives, tuple):
            raise ValueError("presentation snapshot operatives must be an immutable tuple")
        if self.objective_marker is not None and not isinstance(
            self.objective_marker, PresentationPoint
        ):
            raise ValueError("presentation snapshot objective marker must be a presentation point")
        previous_entity_id = 0
        for operative in self.operatives:
            if not isinstance(operative, PresentationOperative):
                raise ValueError("presentation snapshot operatives must be presentation operatives")
            if operative.entity_id <= previous_entity_id:
                raise ValueError("presentation snapshot operatives must be ID ordered")
            previous_entity_id = operative.entity_id


def build_presentation_snapshot(state: MissionState) -> PresentationSnapshot:
    """Copy one authority state into display-only values without changing authority."""
    if not isinstance(state, MissionState):
        raise TypeError("presentation snapshot requires mission state")
    return PresentationSnapshot(
        tick=state.tick,
        phase=state.phase.value,
        map_geometry=(
            None if state.map_geometry is None else _presentation_map(state.map_geometry)
        ),
        operatives=tuple(
            PresentationOperative(
                entity_id=entity.entity_id.value,
                position=_presentation_point(entity.position),
                path=_presentation_path(state, entity.entity_id.value),
            )
            for entity in state.entities
        ),
    )


def _presentation_point(position: object) -> PresentationPoint:
    if not isinstance(position, WorldPosition):
        raise TypeError("presentation point requires a world position")
    return PresentationPoint(
        float(position.x.value), float(position.y.value), position.elevation.value
    )


def _presentation_rectangle(rectangle: object) -> PresentationRectangle:
    if not isinstance(rectangle, WorldRectangle):
        raise TypeError("presentation rectangle requires a world rectangle")
    return PresentationRectangle(
        float(rectangle.minimum_x.value),
        float(rectangle.minimum_y.value),
        float(rectangle.maximum_x.value),
        float(rectangle.maximum_y.value),
    )


def _presentation_map(map_geometry: object) -> PresentationMap:
    if not isinstance(map_geometry, MapGeometry):
        raise TypeError("presentation map requires map geometry")
    return PresentationMap(
        bounds=_presentation_rectangle(map_geometry.bounds),
        obstacles=tuple(
            PresentationObstacle(
                obstacle_id=obstacle.obstacle_id.value,
                bounds=_presentation_rectangle(obstacle.bounds),
                elevation=obstacle.elevation.value,
            )
            for obstacle in map_geometry.obstacles
        ),
    )


def _presentation_path(state: MissionState, entity_id: int) -> tuple[PresentationPoint, ...]:
    for action in state.movement_actions:
        if action.entity_id.value == entity_id:
            return tuple(_presentation_point(waypoint) for waypoint in action.path.waypoints)
    return ()


def capture_authority_snapshot(state: MissionState) -> AuthoritySnapshot:
    """Capture all materialised authority state without presentation data."""
    payload = encode_canonical_state(state)
    return AuthoritySnapshot(
        tick=state.tick,
        canonical_state=payload,
        state_hash=hash_canonical_state_bytes(payload),
    )


def restore_authority_snapshot(snapshot: AuthoritySnapshot) -> SnapshotRestoreResult:
    """Restore one snapshot after validating its payload, tick, and state hash."""
    if not isinstance(snapshot, AuthoritySnapshot):
        raise TypeError("authority snapshot restoration requires an AuthoritySnapshot")
    state = decode_canonical_state(snapshot.canonical_state)
    if isinstance(state, StateDecodeFailure):
        return SnapshotRestoreFailure(
            SnapshotRestoreCode.INVALID_PAYLOAD,
            "snapshot canonical state is invalid",
            state,
        )
    if snapshot.tick != state.tick:
        return SnapshotRestoreFailure(
            SnapshotRestoreCode.TICK_MISMATCH,
            "snapshot tick does not match its canonical state",
        )
    if hash_canonical_state_bytes(snapshot.canonical_state) != snapshot.state_hash:
        return SnapshotRestoreFailure(
            SnapshotRestoreCode.HASH_MISMATCH,
            "snapshot state hash does not match its canonical state",
        )
    return state
