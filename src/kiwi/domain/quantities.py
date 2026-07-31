"""Canonical exact quantities shared by the Kiwi DSL and simulation."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from math import gcd


class QuantityDimension(StrEnum):
    """The dimensions represented by Milestone 4 quantity literals."""

    DURATION = "Duration"
    DISTANCE = "Distance"
    ANGLE = "Angle"
    PROBABILITY = "Probability"


@dataclass(frozen=True, slots=True)
class ExactRational:
    """A signed rational reduced to a positive-denominator canonical form."""

    numerator: int
    denominator: int

    def __post_init__(self) -> None:
        if not isinstance(self.numerator, int) or isinstance(self.numerator, bool):
            raise ValueError("rational numerator must be an integer")
        if not isinstance(self.denominator, int) or isinstance(self.denominator, bool):
            raise ValueError("rational denominator must be an integer")
        if self.denominator <= 0:
            raise ValueError("rational denominator must be positive")
        divisor = gcd(self.numerator, self.denominator)
        object.__setattr__(self, "numerator", self.numerator // divisor)
        object.__setattr__(self, "denominator", self.denominator // divisor)


@dataclass(frozen=True, slots=True)
class Quantity:
    """An exact canonical value with a non-interchangeable dimension tag."""

    dimension: QuantityDimension
    value: ExactRational

    def __post_init__(self) -> None:
        if not isinstance(self.dimension, QuantityDimension):
            raise ValueError("quantity dimension must be a quantity dimension")
        if not isinstance(self.value, ExactRational):
            raise ValueError("quantity value must be an exact rational")


def quantity_from_literal(magnitude: int, suffix: str) -> Quantity:
    """Normalize one non-negative surface literal into its canonical unit."""
    if not isinstance(magnitude, int) or isinstance(magnitude, bool) or magnitude < 0:
        raise ValueError("quantity literal magnitude must be a non-negative integer")
    match suffix:
        case "ms":
            return Quantity(QuantityDimension.DURATION, ExactRational(magnitude, 1_000))
        case "s":
            return Quantity(QuantityDimension.DURATION, ExactRational(magnitude, 1))
        case "m":
            return Quantity(QuantityDimension.DISTANCE, ExactRational(magnitude, 1))
        case "deg":
            return Quantity(QuantityDimension.ANGLE, ExactRational(magnitude, 360))
        case "%":
            if magnitude > 100:
                raise ValueError("probability literal must not exceed 100%")
            return Quantity(QuantityDimension.PROBABILITY, ExactRational(magnitude, 100))
        case _:
            raise ValueError(f"unknown quantity literal suffix {suffix!r}")
