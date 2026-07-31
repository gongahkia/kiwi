from __future__ import annotations

import pytest

from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.dsl.bytecode import (
    BytecodeHeader,
    Call,
    InstructionIndex,
    Jump,
    JumpIfFalse,
    LoadLocal,
    LocalSlot,
    PushConstant,
    PushFunction,
    Return,
    TraceExpression,
)
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.core_ir import CoreModule
from kiwi.dsl.ids import ExpressionId, FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import IntegerValue, QuantityValue, StringValue
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId


def test_compiler_emits_canonical_constants_functions_and_control_flow() -> None:
    source = SourceFile(
        SourceFileId("compile.dtr"),
        "fn identity(x: Int) -> Int = x\n"
        "policy choose(flag: Bool) -> Int = if flag then identity(1) else 2\n",
    )
    module = _core(source)

    compiled = compile_core(module, BytecodeHeader(source.file_id))

    assert compiled.constants.values == (IntegerValue(1), IntegerValue(2))
    identity, choose = compiled.functions
    assert identity.instructions == (
        TraceExpression(ExpressionId(0)),
        LoadLocal(LocalSlot(0)),
        Return(),
    )
    assert choose.instructions[0] == TraceExpression(ExpressionId(1))
    assert choose.instructions[1] == TraceExpression(ExpressionId(2))
    assert isinstance(choose.instructions[2], LoadLocal)
    assert isinstance(choose.instructions[3], JumpIfFalse)
    assert choose.instructions[4] == TraceExpression(ExpressionId(3))
    assert choose.instructions[5] == TraceExpression(ExpressionId(4))
    assert isinstance(choose.instructions[6], PushFunction)
    assert choose.instructions[7] == TraceExpression(ExpressionId(5))
    assert isinstance(choose.instructions[8], PushConstant)
    assert choose.instructions[9] == Call(1)
    assert isinstance(choose.instructions[10], Jump)
    assert choose.instructions[11] == TraceExpression(ExpressionId(6))
    assert isinstance(choose.instructions[12], PushConstant)
    assert choose.instructions[13] == Return()
    assert choose.instructions[3].target.value == 11
    assert choose.instructions[10].target.value == 13
    origin = compiled.source_map.entry_for(FunctionId(1), InstructionIndex(6))
    assert origin.expression_id == ExpressionId(4)
    call_start = source.text.index("identity(1)")
    assert origin.span == source.span(
        ByteOffset(call_start),
        ByteOffset(call_start + len("identity")),
    )


def test_compiler_rejects_header_from_another_source_file() -> None:
    source = SourceFile(SourceFileId("compile.dtr"), "fn value() -> Int = 1")

    with pytest.raises(ValueError, match="source file"):
        compile_core(_core(source), BytecodeHeader(SourceFileId("other.dtr")))


def test_compiler_emits_closed_string_and_exact_quantity_constants() -> None:
    source = SourceFile(
        SourceFileId("literals.dtr"),
        'fn label() -> String = "alpha"\nfn wait() -> Duration = 250ms\n',
    )

    compiled = compile_core(_core(source), BytecodeHeader(source.file_id))

    assert compiled.constants.values == (
        StringValue("alpha"),
        QuantityValue(Quantity(QuantityDimension.DURATION, ExactRational(1, 4))),
    )


def test_compiler_does_not_emit_version_two_values_in_a_legacy_module() -> None:
    source = SourceFile(SourceFileId("legacy-literals.dtr"), 'fn label() -> String = "alpha"')
    legacy_header = BytecodeHeader(source.file_id, 1, 1, 1)

    with pytest.raises(ValueError, match="version 1"):
        compile_core(_core(source), legacy_header)


def _core(source: SourceFile) -> CoreModule:
    checked = check(resolve(parse(lex(source)).module))
    assert checked.module is not None
    return lower(checked.module).module
