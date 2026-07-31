from __future__ import annotations

from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import IntegerValue
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.dsl.syntax import CallExpression, NameExpression, PolicyDeclaration
from kiwi.dsl.vm import run_vm


def test_pipelines_desugar_left_to_right_with_input_as_the_first_argument() -> None:
    source = SourceFile(
        SourceFileId("pipeline.dtr"),
        "fn first(input: Int, ignored: Int) -> Int = input\n"
        "fn identity(input: Int) -> Int = input\n"
        "policy result() -> Int = 7 |> first(9) |> identity\n",
    )
    parsed = parse(lex(source))

    assert parsed.diagnostics == ()
    declaration = parsed.module.declarations[2]
    assert isinstance(declaration, PolicyDeclaration)
    outer = declaration.body
    assert isinstance(outer, CallExpression)
    assert isinstance(outer.callee, NameExpression)
    assert outer.callee.name.text == "identity"
    inner = outer.arguments[0]
    assert isinstance(inner, CallExpression)
    assert isinstance(inner.callee, NameExpression)
    assert inner.callee.name.text == "first"
    input_start = source.text.index("7")
    argument_start = source.text.index("9")
    assert tuple(argument.span for argument in inner.arguments) == (
        source.span(ByteOffset(input_start), ByteOffset(input_start + 1)),
        source.span(ByteOffset(argument_start), ByteOffset(argument_start + 1)),
    )
    pipeline_start = source.text.index("7 |>")
    identity_start = source.text.index("identity", pipeline_start)
    assert outer.span == source.span(ByteOffset(pipeline_start), ByteOffset(identity_start + 8))

    checked = check(resolve(parsed.module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    module = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
    assert run_vm(module, FunctionId(2), ()).value == IntegerValue(7)


def test_pipelines_reuse_ordinary_call_type_diagnostics() -> None:
    source = SourceFile(
        SourceFileId("pipeline-invalid.dtr"),
        "fn identity(input: Int) -> Int = input\nfn invalid() -> Int = true |> identity\n",
    )

    result = check(resolve(parse(lex(source)).module))

    assert result.module is None
    assert tuple(diagnostic.code for diagnostic in result.diagnostics) == ("E401_TYPE_MISMATCH",)
