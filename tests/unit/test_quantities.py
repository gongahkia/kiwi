from __future__ import annotations

import pytest

from kiwi.domain.quantities import ExactRational, QuantityDimension, quantity_from_literal


def test_exact_rationals_and_surface_quantities_have_canonical_units() -> None:
    assert ExactRational(-6, 8) == ExactRational(-3, 4)
    assert ExactRational(0, 99) == ExactRational(0, 1)
    assert quantity_from_literal(250, "ms").dimension is QuantityDimension.DURATION
    assert quantity_from_literal(250, "ms").value == ExactRational(1, 4)
    assert quantity_from_literal(3, "s").value == ExactRational(3, 1)
    assert quantity_from_literal(8, "m").dimension is QuantityDimension.DISTANCE
    assert quantity_from_literal(45, "deg").value == ExactRational(1, 8)
    assert quantity_from_literal(70, "%").value == ExactRational(7, 10)


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: ExactRational(1, 0), "denominator"),
        (lambda: quantity_from_literal(-1, "s"), "non-negative"),
        (lambda: quantity_from_literal(101, "%"), "100%"),
        (lambda: quantity_from_literal(1, "km"), "unknown"),
    ),
)
def test_quantities_reject_noncanonical_or_unsupported_literals(
    factory: object,
    message: str,
) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]
