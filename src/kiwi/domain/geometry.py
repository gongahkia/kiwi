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


@dataclass(frozen=True, slots=True)
class WorldRectangle:
    """A non-empty closed planar axis-aligned rectangle in millimetres."""

    minimum_x: WorldSubunits
    minimum_y: WorldSubunits
    maximum_x: WorldSubunits
    maximum_y: WorldSubunits

    def __post_init__(self) -> None:
        coordinates = (self.minimum_x, self.minimum_y, self.maximum_x, self.maximum_y)
        if not all(isinstance(value, WorldSubunits) for value in coordinates):
            raise ValueError("world rectangle coordinates must be world subunits")
        if self.minimum_x.value >= self.maximum_x.value:
            raise ValueError("world rectangle x bounds must be ascending")
        if self.minimum_y.value >= self.maximum_y.value:
            raise ValueError("world rectangle y bounds must be ascending")

    def contains_position(self, position: WorldPosition) -> bool:
        """Return whether a planar position lies within the closed rectangle."""
        _require_world_position(position, "rectangle position")
        return (
            self.minimum_x.value <= position.x.value <= self.maximum_x.value
            and self.minimum_y.value <= position.y.value <= self.maximum_y.value
        )

    def contains_rectangle(self, rectangle: WorldRectangle) -> bool:
        """Return whether another closed rectangle lies wholly within this rectangle."""
        if not isinstance(rectangle, WorldRectangle):
            raise ValueError("contained rectangle must be a world rectangle")
        return (
            self.minimum_x.value <= rectangle.minimum_x.value
            and self.minimum_y.value <= rectangle.minimum_y.value
            and rectangle.maximum_x.value <= self.maximum_x.value
            and rectangle.maximum_y.value <= self.maximum_y.value
        )


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


def segment_intersects_closed_rectangle(
    start: WorldPosition,
    end: WorldPosition,
    rectangle: WorldRectangle,
) -> bool:
    """Return whether a closed planar segment touches a closed rectangle."""
    _require_world_position(start, "segment start")
    _require_world_position(end, "segment end")
    if not isinstance(rectangle, WorldRectangle):
        raise ValueError("segment rectangle must be a world rectangle")
    start_point = (start.x.value, start.y.value)
    end_point = (end.x.value, end.y.value)
    if _point_in_rectangle(start_point, rectangle) or _point_in_rectangle(end_point, rectangle):
        return True
    minimum_x = rectangle.minimum_x.value
    minimum_y = rectangle.minimum_y.value
    maximum_x = rectangle.maximum_x.value
    maximum_y = rectangle.maximum_y.value
    corners = (
        (minimum_x, minimum_y),
        (minimum_x, maximum_y),
        (maximum_x, maximum_y),
        (maximum_x, minimum_y),
    )
    return any(
        _segments_intersect(start_point, end_point, edge_start, edge_end)
        for edge_start, edge_end in zip(corners, corners[1:] + corners[:1], strict=True)
    )


def _require_world_vector(value: object, label: str) -> None:
    if not isinstance(value, WorldVector):
        raise ValueError(f"{label} must be a world vector")


def _require_world_position(value: object, label: str) -> None:
    if not isinstance(value, WorldPosition):
        raise ValueError(f"{label} must be a world position")


type _PlanarPoint = tuple[int, int]


def _point_in_rectangle(point: _PlanarPoint, rectangle: WorldRectangle) -> bool:
    return (
        rectangle.minimum_x.value <= point[0] <= rectangle.maximum_x.value
        and rectangle.minimum_y.value <= point[1] <= rectangle.maximum_y.value
    )


def _segments_intersect(
    first_start: _PlanarPoint,
    first_end: _PlanarPoint,
    second_start: _PlanarPoint,
    second_end: _PlanarPoint,
) -> bool:
    first_orientation = _orientation(first_start, first_end, second_start)
    second_orientation = _orientation(first_start, first_end, second_end)
    third_orientation = _orientation(second_start, second_end, first_start)
    fourth_orientation = _orientation(second_start, second_end, first_end)
    if first_orientation == 0 and _point_on_segment(second_start, first_start, first_end):
        return True
    if second_orientation == 0 and _point_on_segment(second_end, first_start, first_end):
        return True
    if third_orientation == 0 and _point_on_segment(first_start, second_start, second_end):
        return True
    if fourth_orientation == 0 and _point_on_segment(first_end, second_start, second_end):
        return True
    return (first_orientation > 0) != (second_orientation > 0) and (third_orientation > 0) != (
        fourth_orientation > 0
    )


def _orientation(start: _PlanarPoint, end: _PlanarPoint, point: _PlanarPoint) -> int:
    return (end[0] - start[0]) * (point[1] - start[1]) - (end[1] - start[1]) * (point[0] - start[0])


def _point_on_segment(point: _PlanarPoint, start: _PlanarPoint, end: _PlanarPoint) -> bool:
    return min(start[0], end[0]) <= point[0] <= max(start[0], end[0]) and min(
        start[1], end[1]
    ) <= point[1] <= max(start[1], end[1])
