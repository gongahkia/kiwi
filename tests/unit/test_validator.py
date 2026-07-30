from __future__ import annotations

from dataclasses import replace

from kiwi.dsl.bytecode import (
    BytecodeHeader,
    ConstantId,
    InstructionIndex,
    Jump,
    PushConstant,
    Return,
)
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.core_ir import CoreModule
from kiwi.dsl.ids import DefinitionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.validator import BytecodeValidationCode, validate_bytecode


def test_validator_accepts_compiler_output() -> None:
    source = SourceFile(SourceFileId("valid.dtr"), "fn value() -> Int = 1")

    result = validate_bytecode(compile_core(_core(source), BytecodeHeader(source.file_id)))

    assert result.is_valid
    assert result.errors == ()


def test_validator_rejects_structural_and_control_flow_faults() -> None:
    source = SourceFile(SourceFileId("invalid.dtr"), "fn value() -> Int = 1")
    compiled = compile_core(_core(source), BytecodeHeader(source.file_id))
    function = compiled.functions[0]
    invalid = replace(
        compiled,
        functions=(
            replace(
                function,
                definition_id=DefinitionId(7),
                instructions=(PushConstant(ConstantId(3)),),
            ),
        ),
    )

    result = validate_bytecode(invalid)

    assert not result.is_valid
    assert tuple(error.code for error in result.errors) == (
        BytecodeValidationCode.FUNCTION_TABLE_MISMATCH,
        BytecodeValidationCode.INVALID_CONSTANT,
        BytecodeValidationCode.CONTROL_FLOW_FALLTHROUGH,
    )


def test_validator_rejects_stack_underflow_before_execution() -> None:
    source = SourceFile(SourceFileId("underflow.dtr"), "fn value() -> Int = 1")
    compiled = compile_core(_core(source), BytecodeHeader(source.file_id))
    invalid = replace(
        compiled, functions=(replace(compiled.functions[0], instructions=(Return(),)),)
    )

    result = validate_bytecode(invalid)

    assert [error.code for error in result.errors] == [BytecodeValidationCode.STACK_UNDERFLOW]


def test_validator_rejects_jump_target_before_flow_analysis() -> None:
    source = SourceFile(SourceFileId("jump.dtr"), "fn value() -> Int = 1")
    compiled = compile_core(_core(source), BytecodeHeader(source.file_id))
    invalid = replace(
        compiled,
        functions=(
            replace(
                compiled.functions[0],
                instructions=(PushConstant(ConstantId(0)), Jump(InstructionIndex(4))),
            ),
        ),
    )

    result = validate_bytecode(invalid)

    assert [error.code for error in result.errors] == [BytecodeValidationCode.INVALID_JUMP]


def _core(source: SourceFile) -> CoreModule:
    checked = check(resolve(parse(lex(source)).module))
    assert checked.module is not None
    return lower(checked.module).module
