from __future__ import annotations

import pytest

from kiwi.dsl.bytecode import (
    ConstantPool,
    ConstantPoolBuilder,
    FunctionTable,
    FunctionTableEntry,
    canonical_function_table,
)
from kiwi.dsl.checker import check
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import BooleanValue, FunctionValue, IntegerValue, UnitValue
from kiwi.dsl.source import SourceFile, SourceFileId


def test_constant_pool_interns_first_explicit_encounter_order() -> None:
    builder = ConstantPoolBuilder()

    first = builder.intern(IntegerValue(7))
    second = builder.intern(BooleanValue(True))
    repeated = builder.intern(IntegerValue(7))
    third = builder.intern(UnitValue())
    pool = builder.freeze()

    assert (first.value, second.value, repeated.value, third.value) == (0, 1, 0, 2)
    assert pool.values == (IntegerValue(7), BooleanValue(True), UnitValue())
    with pytest.raises(ValueError, match="runtime constants"):
        builder.intern(FunctionValue(FunctionId(0)))  # type: ignore[arg-type]
    with pytest.raises(ValueError, match="unique"):
        ConstantPool((IntegerValue(7), IntegerValue(7)))


def test_function_table_uses_definition_id_order_independent_of_input_order() -> None:
    source = SourceFile(
        SourceFileId("functions.dtr"),
        "fn first() -> Int = 1\nfn second(x: Int) -> Int = x\n",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.module is not None
    lowered = lower(checked.module)
    table = canonical_function_table(tuple(reversed(lowered.module.definitions)))

    assert [
        (entry.function_id.value, entry.definition_id.value, entry.name, entry.arity)
        for entry in table.entries
    ] == [
        (0, 0, "first", 0),
        (1, 1, "second", 1),
    ]
    assert table.function_id_for(lowered.module.definitions[1].definition_id) == FunctionId(1)
    with pytest.raises(ValueError, match="contiguous"):
        FunctionTable(
            (
                FunctionTableEntry(
                    FunctionId(1), lowered.module.definitions[0].definition_id, "first", 0
                ),
            )
        )
