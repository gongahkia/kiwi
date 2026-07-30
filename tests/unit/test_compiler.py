from __future__ import annotations

import pytest

from kiwi.dsl.bytecode import (
    BytecodeHeader,
    Call,
    Jump,
    JumpIfFalse,
    LoadLocal,
    LocalSlot,
    PushConstant,
    PushFunction,
    Return,
)
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.core_ir import CoreModule
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import IntegerValue
from kiwi.dsl.source import SourceFile, SourceFileId


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
    assert identity.instructions == (LoadLocal(LocalSlot(0)), Return())
    assert isinstance(choose.instructions[0], LoadLocal)
    assert isinstance(choose.instructions[1], JumpIfFalse)
    assert isinstance(choose.instructions[2], PushFunction)
    assert isinstance(choose.instructions[3], PushConstant)
    assert choose.instructions[4] == Call(1)
    assert isinstance(choose.instructions[5], Jump)
    assert isinstance(choose.instructions[6], PushConstant)
    assert choose.instructions[7] == Return()
    assert choose.instructions[1].target.value == 6
    assert choose.instructions[5].target.value == 7


def test_compiler_rejects_header_from_another_source_file() -> None:
    source = SourceFile(SourceFileId("compile.dtr"), "fn value() -> Int = 1")

    with pytest.raises(ValueError, match="source file"):
        compile_core(_core(source), BytecodeHeader(SourceFileId("other.dtr")))


def _core(source: SourceFile) -> CoreModule:
    checked = check(resolve(parse(lex(source)).module))
    assert checked.module is not None
    return lower(checked.module).module
