from __future__ import annotations

import pytest

from kiwi.dsl.bytecode import (
    BytecodeHeader,
    JumpIfNone,
    Pop,
    UnwrapSome,
)
from kiwi.dsl.bytecode_codec import decode_bytecode, encode_bytecode
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import ParserDiagnosticCode, parse
from kiwi.dsl.runtime_values import IntegerValue, OptionNoneValue, OptionSomeValue
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.vm import run_vm


def test_exhaustive_option_matches_compile_encode_and_execute() -> None:
    source = SourceFile(
        SourceFileId("matching.dtr"),
        "fn choose(value: Option<Int>) -> Int = match value with "
        "| Some(item) -> item | None -> 0\n"
        "policy nested(value: Option<Option<Int>>) -> Int = match value with "
        "| None -> 0 | Some(inner) -> match inner with "
        "| Some(item) -> item | None -> -1\n",
    )
    parsed = parse(lex(source))
    checked = check(resolve(parsed.module))

    assert parsed.diagnostics == ()
    assert checked.diagnostics == ()
    assert checked.module is not None
    module = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
    instructions = tuple(
        instruction for function in module.functions for instruction in function.instructions
    )
    assert any(isinstance(instruction, JumpIfNone) for instruction in instructions)
    assert any(isinstance(instruction, UnwrapSome) for instruction in instructions)
    assert any(isinstance(instruction, Pop) for instruction in instructions)

    assert run_vm(module, FunctionId(0), (OptionSomeValue(IntegerValue(7)),)).value == IntegerValue(
        7
    )
    assert run_vm(module, FunctionId(0), (OptionNoneValue(),)).value == IntegerValue(0)
    assert run_vm(
        module,
        FunctionId(1),
        (OptionSomeValue(OptionSomeValue(IntegerValue(9))),),
    ).value == IntegerValue(9)
    assert run_vm(
        module, FunctionId(1), (OptionSomeValue(OptionNoneValue()),)
    ).value == IntegerValue(-1)
    assert run_vm(module, FunctionId(1), (OptionNoneValue(),)).value == IntegerValue(0)
    assert decode_bytecode(encode_bytecode(module)) == module


def test_matches_report_static_subject_exhaustiveness_duplicate_and_branch_errors() -> None:
    source = SourceFile(
        SourceFileId("matching-invalid.dtr"),
        "fn incomplete(value: Option<Int>) -> Int = match value with | Some(item) -> item\n"
        "fn duplicate(value: Option<Int>) -> Int = match value with "
        "| Some(first) -> first | Some(second) -> second | None -> 0\n"
        "fn plain(value: Int) -> Int = match value with | Some(item) -> item | None -> 0\n"
        "fn mismatch(value: Option<Int>) -> Int = match value with "
        "| Some(item) -> item | None -> false\n",
    )

    result = check(resolve(parse(lex(source)).module))

    assert result.module is None
    assert tuple(diagnostic.code for diagnostic in result.diagnostics) == (
        "E415_INCOMPLETE_MATCH",
        "E414_DUPLICATE_MATCH_ARM",
        "E413_INVALID_MATCH_SUBJECT",
        "E416_MATCH_BRANCH_TYPE",
    )


@pytest.mark.parametrize(
    ("text", "code"),
    (
        ("fn bad(v: Option<Int>) -> Int = match v with", ParserDiagnosticCode.EXPECTED_TOKEN),
        (
            "fn bad(v: Option<Int>) -> Int = match v with | value -> value",
            ParserDiagnosticCode.EXPECTED_PATTERN,
        ),
    ),
)
def test_match_parser_returns_stable_diagnostics(text: str, code: ParserDiagnosticCode) -> None:
    result = parse(lex(SourceFile(SourceFileId("matching-parse.dtr"), text)))

    assert result.module.declarations == ()
    assert result.diagnostics[-1].code == code
