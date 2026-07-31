"""Canonical integer geometry for authoritative simulation state."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension

WORLD_SUBUNITS_PER_METRE = 1_000
MIN_WORLD_SUBUNITS = -(1 << 63)
MAX_WORLD_SUBUNITS = (1 << 63) - 1


@dataclass(frozen=True, slots=True)
class WorldSubunits:
    """A signed 64-bit distance or coordinate measured in millimetres."""

    value: int

    def __post_init__(self) -> None:
        if not isinstance(self.value, int) or isinstance(self.value, bool):
            raise ValueError("world subunits must be an integer")
        if not MIN_WORLD_SUBUNITS <= self.value <= MAX_WORLD_SUBUNITS:
            raise ValueError("world subunits must fit signed 64-bit range")


@dataclass(frozen=True, slots=True)
class ElevationLayer:
    """A non-negative discrete authoritative elevation layer."""

    value: int = 0

    def __post_init__(self) -> None:
        if not isinstance(self.value, int) or isinstance(self.value, bool):
            raise ValueError("elevation layer must be an integer")
        if not 0 <= self.value <= MAX_WORLD_SUBUNITS:
            raise ValueError("elevation layer must fit non-negative signed 64-bit range")


@dataclass(frozen=True, slots=True)
class WorldVector:
    """A planar canonical displacement in millimetres."""

    dx: WorldSubunits
    dy: WorldSubunits

    def __post_init__(self) -> None:
        if not isinstance(self.dx, WorldSubunits) or not isinstance(self.dy, WorldSubunits):
            raise ValueError("world vector components must be world subunits")


@dataclass(frozen=True, slots=True)
class WorldPosition:
    """A planar position with an explicit discrete elevation layer."""

    x: WorldSubunits
    y: WorldSubunits
    elevation: ElevationLayer = ElevationLayer()

    def __post_init__(self) -> None:
        if not isinstance(self.x, WorldSubunits) or not isinstance(self.y, WorldSubunits):
            raise ValueError("world position coordinates must be world subunits")
        if not isinstance(self.elevation, ElevationLayer):
            raise ValueError("world position elevation must be an elevation layer")


def round_nearest_ties_away_from_zero(numerator: int, denominator: int) -> int:
    """Divide with nearest rounding and deterministic away-from-zero ties."""
    if not isinstance(numerator, int) or isinstance(numerator, bool):
        raise ValueError("rounding numerator must be an integer")
    if not isinstance(denominator, int) or isinstance(denominator, bool) or denominator <= 0:
        raise ValueError("rounding denominator must be a positive integer")
    quotient, remainder = divmod(abs(numerator), denominator)
    if remainder * 2 >= denominator:
        quotient += 1
    return -quotient if numerator < 0 else quotient


def world_subunits_from_distance(distance: Quantity) -> WorldSubunits:
    """Convert one exact DSL distance to canonical millimetres at the sim boundary."""
    if not isinstance(distance, Quantity) or distance.dimension is not QuantityDimension.DISTANCE:
        raise ValueError("world distance conversion requires a Distance quantity")
    value = distance.value
    return WorldSubunits(
        round_nearest_ties_away_from_zero(
            value.numerator * WORLD_SUBUNITS_PER_METRE,
            value.denominator,
        )
    )


def distance_from_world_subunits(value: WorldSubunits) -> Quantity:
    """Convert canonical millimetres to the exact DSL distance representation."""
    if not isinstance(value, WorldSubunits):
        raise ValueError("world distance must be world subunits")
    return Quantity(
        dimension=QuantityDimension.DISTANCE,
        value=ExactRational(value.value, WORLD_SUBUNITS_PER_METRE),
    )


def add_vectors(left: WorldVector, right: WorldVector) -> WorldVector:
    """Add two planar vectors, rejecting 64-bit overflow."""
    _require_world_vector(left, "left vector")
    _require_world_vector(right, "right vector")
    return WorldVector(
        dx=WorldSubunits(left.dx.value + right.dx.value),
        dy=WorldSubunits(left.dy.value + right.dy.value),
    )


def subtract_vectors(left: WorldVector, right: WorldVector) -> WorldVector:
    """Subtract two planar vectors, rejecting 64-bit overflow."""
    _require_world_vector(left, "left vector")
    _require_world_vector(right, "right vector")
    return WorldVector(
        dx=WorldSubunits(left.dx.value - right.dx.value),
        dy=WorldSubunits(left.dy.value - right.dy.value),
    )


def translate(position: WorldPosition, vector: WorldVector) -> WorldPosition:
    """Translate one position in its current elevation layer."""
    _require_world_position(position, "position")
    _require_world_vector(vector, "vector")
    return WorldPosition(
        x=WorldSubunits(position.x.value + vector.dx.value),
        y=WorldSubunits(position.y.value + vector.dy.value),
        elevation=position.elevation,
    )


def displacement(start: WorldPosition, end: WorldPosition) -> WorldVector:
    """Return a planar displacement; cross-layer displacement is not implicit."""
    _require_world_position(start, "start position")
    _require_world_position(end, "end position")
    if start.elevation != end.elevation:
        raise ValueError("planar displacement requires matching elevation layers")
    return WorldVector(
        dx=WorldSubunits(end.x.value - start.x.value),
        dy=WorldSubunits(end.y.value - start.y.value),
    )


def _require_world_vector(value: object, label: str) -> None:
    if not isinstance(value, WorldVector):
        raise ValueError(f"{label} must be a world vector")


def _require_world_position(value: object, label: str) -> None:
    if not isinstance(value, WorldPosition):
        raise ValueError(f"{label} must be a world position")
