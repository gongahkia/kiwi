from __future__ import annotations

from typing import cast

import pytest

from kiwi.domain.geometry import (
    MAX_WORLD_SUBUNITS,
    MIN_WORLD_SUBUNITS,
    ElevationLayer,
    WorldPosition,
    WorldRectangle,
    WorldSubunits,
    WorldVector,
    add_vectors,
    displacement,
    distance_from_world_subunits,
    round_nearest_ties_away_from_zero,
    subtract_vectors,
    translate,
    world_subunits_from_distance,
)
from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension, quantity_from_literal


def distance(numerator: int, denominator: int = 1) -> Quantity:
    return Quantity(QuantityDimension.DISTANCE, ExactRational(numerator, denominator))


def test_exact_distances_convert_to_signed_64_bit_millimetres() -> None:
    assert world_subunits_from_distance(quantity_from_literal(2, "m")) == WorldSubunits(2_000)
    assert world_subunits_from_distance(distance(1, 2)) == WorldSubunits(500)
    assert world_subunits_from_distance(distance(1, 2_000)) == WorldSubunits(1)
    assert world_subunits_from_distance(distance(-1, 2_000)) == WorldSubunits(-1)
    assert world_subunits_from_distance(distance(49, 100_000)) == WorldSubunits(0)
    assert world_subunits_from_distance(distance(-51, 100_000)) == WorldSubunits(-1)


def test_world_distance_round_trip_is_exact_in_metres() -> None:
    assert distance_from_world_subunits(WorldSubunits(-1_250)) == distance(-5, 4)


def test_world_rectangles_are_nonempty_and_include_their_boundaries() -> None:
    bounds = WorldRectangle(
        WorldSubunits(-10), WorldSubunits(-20), WorldSubunits(30), WorldSubunits(40)
    )
    nested = WorldRectangle(
        WorldSubunits(-10), WorldSubunits(-20), WorldSubunits(30), WorldSubunits(40)
    )

    assert bounds.contains_position(WorldPosition(WorldSubunits(-10), WorldSubunits(40)))
    assert not bounds.contains_position(WorldPosition(WorldSubunits(31), WorldSubunits(40)))
    assert bounds.contains_rectangle(nested)


@pytest.mark.parametrize(
    ("numerator", "denominator", "expected"),
    (
        (1, 2, 1),
        (-1, 2, -1),
        (3, 2, 2),
        (-3, 2, -2),
        (1, 3, 0),
        (-1, 3, 0),
    ),
)
def test_rounding_is_nearest_with_away_from_zero_ties(
    numerator: int,
    denominator: int,
    expected: int,
) -> None:
    assert round_nearest_ties_away_from_zero(numerator, denominator) == expected


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: WorldSubunits(MIN_WORLD_SUBUNITS - 1), "signed 64-bit"),
        (lambda: WorldSubunits(MAX_WORLD_SUBUNITS + 1), "signed 64-bit"),
        (lambda: ElevationLayer(-1), "non-negative"),
        (lambda: ElevationLayer(MAX_WORLD_SUBUNITS + 1), "signed 64-bit"),
        (lambda: world_subunits_from_distance(quantity_from_literal(1, "s")), "Distance"),
        (lambda: world_subunits_from_distance(distance(MAX_WORLD_SUBUNITS + 1, 1_000)), "signed"),
        (lambda: round_nearest_ties_away_from_zero(1, 0), "positive"),
        (
            lambda: WorldRectangle(
                WorldSubunits(1), WorldSubunits(0), WorldSubunits(1), WorldSubunits(2)
            ),
            "x bounds",
        ),
        (
            lambda: WorldRectangle(
                WorldSubunits(0), WorldSubunits(2), WorldSubunits(1), WorldSubunits(1)
            ),
            "y bounds",
        ),
        (
            lambda: WorldRectangle(
                WorldSubunits(0),
                WorldSubunits(0),
                cast(WorldSubunits, 1),
                WorldSubunits(2),
            ),
            "coordinates",
        ),
    ),
)
def test_canonical_geometry_rejects_invalid_or_out_of_range_values(
    factory: object,
    message: str,
) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]


def test_planar_geometry_preserves_elevation_and_checks_overflow() -> None:
    origin = WorldPosition(WorldSubunits(10), WorldSubunits(-20), ElevationLayer(2))
    offset = WorldVector(WorldSubunits(3), WorldSubunits(5))
    destination = WorldPosition(WorldSubunits(13), WorldSubunits(-15), ElevationLayer(2))

    assert translate(origin, offset) == destination
    assert displacement(origin, destination) == offset
    assert add_vectors(offset, offset) == WorldVector(WorldSubunits(6), WorldSubunits(10))
    assert subtract_vectors(offset, offset) == WorldVector(WorldSubunits(0), WorldSubunits(0))

    with pytest.raises(ValueError, match="matching elevation"):
        displacement(
            origin, WorldPosition(WorldSubunits(10), WorldSubunits(-20), ElevationLayer(3))
        )
    with pytest.raises(ValueError, match="signed 64-bit"):
        translate(
            WorldPosition(WorldSubunits(MAX_WORLD_SUBUNITS), WorldSubunits(0)),
            WorldVector(WorldSubunits(1), WorldSubunits(0)),
        )
