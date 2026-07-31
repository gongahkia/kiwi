from __future__ import annotations

from dataclasses import FrozenInstanceError

import pytest

from kiwi.dsl.bytecode import (
    BuildRecord,
    Call,
    ConstantId,
    InstructionIndex,
    Jump,
    JumpIfFalse,
    LoadField,
    LoadLocal,
    LocalSlot,
    Negate,
    Opcode,
    PushConstant,
    PushFunction,
    Return,
    StoreLocal,
    TraceExpression,
)
from kiwi.dsl.ids import ExpressionId, FunctionId


def test_initial_instruction_set_uses_stable_numeric_opcodes() -> None:
    instructions = (
        PushConstant(ConstantId(0)),
        PushFunction(FunctionId(0)),
        LoadLocal(LocalSlot(0)),
        StoreLocal(LocalSlot(1)),
        Negate(),
        Call(2),
        Jump(InstructionIndex(5)),
        JumpIfFalse(InstructionIndex(6)),
        Return(),
        TraceExpression(ExpressionId(7)),
        BuildRecord("Point", ("x",)),
        LoadField("x"),
    )

    assert tuple(instruction.opcode for instruction in instructions) == tuple(Opcode)
    with pytest.raises(FrozenInstanceError):
        instructions[0].constant_id = ConstantId(1)  # type: ignore[misc]


def test_instruction_operands_reject_invalid_indices_and_counts() -> None:
    with pytest.raises(ValueError, match="constant ID"):
        ConstantId(-1)
    with pytest.raises(ValueError, match="local slot"):
        LocalSlot(True)
    with pytest.raises(ValueError, match="instruction index"):
        InstructionIndex(-1)
    with pytest.raises(ValueError, match="argument count"):
        Call(-1)
    with pytest.raises(ValueError, match="unique"):
        BuildRecord("Point", ("x", "x"))
    with pytest.raises(ValueError, match="field name"):
        LoadField("")
