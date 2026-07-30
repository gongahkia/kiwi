from __future__ import annotations

from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.disassemble import disassemble
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.source import SourceFile, SourceFileId


def test_disassembler_renders_stable_bytecode_text() -> None:
    source = SourceFile(SourceFileId("disassemble.dtr"), "fn value() -> Int = -1")
    checked = check(resolve(parse(lex(source)).module))

    assert checked.module is not None
    compiled = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
    assert (
        disassemble(compiled)
        == """BytecodeModule source='disassemble.dtr' language=1 core=1 bytecode=1
  constants:
    0: Integer(1)
  function_table:
    0: definition=0 name='value' arity=0
  functions:
    Function 0 definition=0 name='value' arity=0 locals=0 return=Int
      0000 PUSH_CONSTANT 0
      0001 NEGATE
      0002 RETURN"""
    )
