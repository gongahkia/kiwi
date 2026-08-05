from __future__ import annotations

from dataclasses import FrozenInstanceError

import pytest

from kiwi.domain.ids import EventId
from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.runtime_values import (
    BooleanValue,
    ClosureValue,
    FunctionValue,
    IntegerValue,
    ListValue,
    ObservationFieldMetadata,
    OptionNoneValue,
    OptionSomeValue,
    QuantityValue,
    RecordValue,
    RuntimeValueKind,
    StringValue,
    UnitValue,
    strip_observation_metadata,
)


def test_runtime_values_are_closed_immutable_tagged_values() -> None:
    values = (
        IntegerValue(-7),
        BooleanValue(True),
        UnitValue(),
        StringValue("alpha"),
        QuantityValue(Quantity(QuantityDimension.DURATION, ExactRational(1, 4))),
        OptionSomeValue(IntegerValue(1)),
        OptionNoneValue(),
        ListValue((IntegerValue(1),)),
        RecordValue("Point", ("x",), (IntegerValue(1),)),
        FunctionValue(FunctionId(3)),
        ClosureValue(FunctionId(3), (IntegerValue(1),)),
    )

    assert tuple(value.kind for value in values) == (
        RuntimeValueKind.INTEGER,
        RuntimeValueKind.BOOLEAN,
        RuntimeValueKind.UNIT,
        RuntimeValueKind.STRING,
        RuntimeValueKind.QUANTITY,
        RuntimeValueKind.OPTION_SOME,
        RuntimeValueKind.OPTION_NONE,
        RuntimeValueKind.LIST,
        RuntimeValueKind.RECORD,
        RuntimeValueKind.FUNCTION,
        RuntimeValueKind.CLOSURE,
    )
    with pytest.raises(FrozenInstanceError):
        values[0].value = 1  # type: ignore[misc]


def test_runtime_values_reject_host_type_confusion() -> None:
    with pytest.raises(ValueError, match="integer"):
        IntegerValue(True)
    with pytest.raises(ValueError, match="boolean"):
        BooleanValue(1)  # type: ignore[arg-type]
    with pytest.raises(ValueError, match="function ID"):
        FunctionId(-1)
    with pytest.raises(ValueError, match="function value"):
        FunctionValue(1)  # type: ignore[arg-type]
    with pytest.raises(ValueError, match="closure captures"):
        ClosureValue(FunctionId(1), (1,))  # type: ignore[arg-type]
    with pytest.raises(ValueError, match="string"):
        StringValue(1)  # type: ignore[arg-type]
    with pytest.raises(ValueError, match="quantity"):
        QuantityValue(1)  # type: ignore[arg-type]
    with pytest.raises(ValueError, match="lexically"):
        RecordValue("Point", ("y", "x"), (IntegerValue(1), IntegerValue(2)))


def test_observation_metadata_is_validated_and_stripped_from_returned_values() -> None:
    metadata = ObservationFieldMetadata(("self", "health"), (EventId(1),), 7_500, 3)
    observed = RecordValue(
        "SelfObservation",
        ("health",),
        (IntegerValue(2),),
        observation_fields=(metadata,),
    )
    returned = RecordValue("Memory", ("snapshot",), (observed,))

    stripped = strip_observation_metadata(returned)

    assert observed.observation_field_metadata("health") == metadata
    assert isinstance(stripped, RecordValue)
    nested = stripped.field_value("snapshot")
    assert isinstance(nested, RecordValue)
    assert nested.observation_fields == ()
    with pytest.raises(ValueError, match="cover every field"):
        RecordValue(
            "SelfObservation",
            ("health",),
            (IntegerValue(2),),
            observation_fields=(metadata, metadata),
        )
