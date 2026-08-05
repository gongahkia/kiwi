from __future__ import annotations

import pytest

from kiwi.domain.ids import EntityId
from kiwi.sim.conditions import (
    MAX_OPERATIVE_HEALTH,
    MAX_OPERATIVE_PROTECTION,
    InjurySeverity,
    OperativeCondition,
    OperativeConditionStore,
)


def test_absent_condition_is_a_healthy_protected_default() -> None:
    store = OperativeConditionStore()

    condition = store.condition_for(EntityId(1))

    assert condition.health == MAX_OPERATIVE_HEALTH
    assert condition.protection == MAX_OPERATIVE_PROTECTION
    assert condition.injury_severity is InjurySeverity.NONE
    assert not condition.incapacitated
    assert condition.is_default


def test_condition_store_is_sparse_entity_ordered_and_supports_explicit_lookup() -> None:
    first = OperativeCondition(EntityId(1), 2, 0)
    second = OperativeCondition(EntityId(2), 0, 0, True)
    store = OperativeConditionStore().with_condition(second).with_condition(first)

    assert store.entries == (first, second)
    assert store.condition_for(EntityId(1)) == first
    assert store.is_incapacitated(EntityId(2))
    assert store.with_condition(OperativeCondition(EntityId(1))) == OperativeConditionStore(
        (second,)
    )


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: OperativeCondition(EntityId(1), -1), "health"),
        (
            lambda: OperativeCondition(EntityId(1), MAX_OPERATIVE_HEALTH + 1),
            "health",
        ),
        (lambda: OperativeCondition(EntityId(1), protection=-1), "protection"),
        (
            lambda: OperativeCondition(EntityId(1), protection=MAX_OPERATIVE_PROTECTION + 1),
            "protection",
        ),
        (
            lambda: OperativeConditionStore((OperativeCondition(EntityId(1)),)),
            "omit default",
        ),
        (
            lambda: OperativeConditionStore(
                (OperativeCondition(EntityId(2), 2, 0), OperativeCondition(EntityId(1), 2, 0))
            ),
            "entity-ID ordered",
        ),
    ),
)
def test_conditions_reject_noncanonical_values(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]
