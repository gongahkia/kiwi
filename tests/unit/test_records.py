from __future__ import annotations

import pytest

from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.dsl.bytecode import BuildRecord, BytecodeHeader, LoadField
from kiwi.dsl.bytecode_codec import decode_bytecode, encode_bytecode
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import QuantityValue, RecordValue, StringValue
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.vm import run_vm


def test_records_parse_check_compile_encode_and_access_fields_deterministically() -> None:
    source = SourceFile(
        SourceFileId("records.dtr"),
        "type Pair = { duration: Duration, label: String }\n"
        'fn make() -> Pair = Pair { label = "alpha", duration = 250ms }\n'
        "policy label() -> String = make().label\n"
        "policy wait() -> Duration = make().duration\n",
    )
    parsed = parse(lex(source))
    checked = check(resolve(parsed.module))

    assert parsed.diagnostics == ()
    assert checked.diagnostics == ()
    assert checked.module is not None
    module = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
    assert any(
        isinstance(instruction, BuildRecord) for instruction in module.functions[0].instructions
    )
    assert any(
        isinstance(instruction, LoadField) for instruction in module.functions[1].instructions
    )

    record = run_vm(module, FunctionId(0), ())
    label = run_vm(module, FunctionId(1), ())
    wait = run_vm(module, FunctionId(2), ())

    assert record.value == RecordValue(
        "Pair",
        ("duration", "label"),
        (
            QuantityValue(Quantity(QuantityDimension.DURATION, ExactRational(1, 4))),
            StringValue("alpha"),
        ),
    )
    assert record.fault is None
    assert label.value == StringValue("alpha")
    assert label.fault is None
    assert wait.value == QuantityValue(Quantity(QuantityDimension.DURATION, ExactRational(1, 4)))
    assert wait.fault is None
    assert decode_bytecode(encode_bytecode(module)) == module


def test_records_report_static_schema_and_field_access_diagnostics() -> None:
    source = SourceFile(
        SourceFileId("records-invalid.dtr"),
        "type Point = { x: Int }\nfn missing() -> Point = Point { }\nfn field() -> Int = 1.x\n",
    )

    result = check(resolve(parse(lex(source)).module))

    assert result.module is None
    assert tuple(diagnostic.code for diagnostic in result.diagnostics) == (
        "E409_MISSING_RECORD_FIELD",
        "E410_INVALID_FIELD_ACCESS",
    )


def test_legacy_bytecode_does_not_accept_record_instructions() -> None:
    source = SourceFile(
        SourceFileId("legacy-record.dtr"),
        "type Point = { x: Int }\nfn point() -> Point = Point { x = 1 }\n",
    )
    checked = check(resolve(parse(lex(source)).module))
    assert checked.module is not None

    with pytest.raises(ValueError, match="version 1"):
        compile_core(lower(checked.module).module, BytecodeHeader(source.file_id, 1, 1, 1))
