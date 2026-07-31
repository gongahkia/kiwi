from __future__ import annotations

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits, distance_from_world_subunits
from kiwi.domain.ids import EntityId
from kiwi.dsl.runtime_values import IntegerValue, QuantityValue, RecordValue
from kiwi.sim.observations import (
    OBSERVATION_RECORD_TYPE,
    OBSERVATION_SCHEMA_VERSION,
    POSITION_RECORD_TYPE,
    SELF_OBSERVATION_RECORD_TYPE,
    RuntimeObservation,
    SelfObservation,
    observation_runtime_value,
)


def test_runtime_observation_converts_to_the_versioned_closed_dsl_layout() -> None:
    observation = RuntimeObservation(
        SelfObservation(EntityId(4), WorldPosition(WorldSubunits(-2_000), WorldSubunits(500))),
        tick=9,
    )

    value = observation_runtime_value(observation)

    assert OBSERVATION_SCHEMA_VERSION == 1
    assert value.type_name == OBSERVATION_RECORD_TYPE
    assert value.field_names == ("self", "tick")
    self_value = value.field_value("self")
    assert isinstance(self_value, RecordValue)
    assert self_value.type_name == SELF_OBSERVATION_RECORD_TYPE
    assert self_value.field_names == ("entity_id", "position")
    assert self_value.field_value("entity_id") == IntegerValue(4)
    position_value = self_value.field_value("position")
    assert isinstance(position_value, RecordValue)
    assert position_value.type_name == POSITION_RECORD_TYPE
    assert position_value.field_names == ("x", "y")
    assert position_value.field_value("x") == QuantityValue(
        distance_from_world_subunits(WorldSubunits(-2_000))
    )
    assert position_value.field_value("y") == QuantityValue(
        distance_from_world_subunits(WorldSubunits(500))
    )
    assert value.field_value("tick") == IntegerValue(9)


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (
            lambda: SelfObservation(EntityId(1), object()),  # type: ignore[arg-type]
            "world position",
        ),
        (
            lambda: RuntimeObservation(object(), 0),  # type: ignore[arg-type]
            "self observation",
        ),
        (
            lambda: RuntimeObservation(
                SelfObservation(EntityId(1), WorldPosition(WorldSubunits(0), WorldSubunits(0))),
                -1,
            ),
            "non-negative",
        ),
        (lambda: observation_runtime_value(object()), "RuntimeObservation"),  # type: ignore[arg-type]
    ),
)
def test_runtime_observation_schema_rejects_invalid_values(factory: object, message: str) -> None:
    with pytest.raises((TypeError, ValueError), match=message):
        factory()  # type: ignore[operator]
