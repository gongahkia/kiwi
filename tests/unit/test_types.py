from __future__ import annotations

import pytest

from kiwi.dsl.types import BuiltinType, FunctionType, NamedType, render_type


def test_type_renderer_uses_canonical_function_associativity() -> None:
    assert render_type(BuiltinType.INT) == "Int"
    assert render_type(NamedType("Observation")) == "Observation"
    assert render_type(FunctionType((BuiltinType.INT,), BuiltinType.BOOL)) == "Int -> Bool"
    assert (
        render_type(FunctionType((BuiltinType.INT, BuiltinType.BOOL), BuiltinType.UNIT))
        == "(Int, Bool) -> Unit"
    )
    assert (
        render_type(
            FunctionType((FunctionType((BuiltinType.INT,), BuiltinType.BOOL),), BuiltinType.UNIT)
        )
        == "(Int -> Bool) -> Unit"
    )
    assert (
        render_type(
            FunctionType((BuiltinType.INT,), FunctionType((BuiltinType.BOOL,), BuiltinType.UNIT))
        )
        == "Int -> Bool -> Unit"
    )


def test_type_algebra_rejects_invalid_shapes() -> None:
    with pytest.raises(ValueError, match="must not be empty"):
        NamedType("")
    with pytest.raises(ValueError, match="at least one parameter"):
        FunctionType((), BuiltinType.INT)
    with pytest.raises(TypeError, match="parameters"):
        FunctionType(("Int",), BuiltinType.INT)  # type: ignore[arg-type]
    with pytest.raises(TypeError, match="return"):
        FunctionType((BuiltinType.INT,), "Int")  # type: ignore[arg-type]
