from __future__ import annotations

import pytest

from kiwi.dsl.bytecode import (
    LEGACY_BYTECODE_VERSION,
    LEGACY_CORE_IR_VERSION,
    LEGACY_SOURCE_LANGUAGE_VERSION,
    BytecodeFunction,
    BytecodeHeader,
    BytecodeModule,
    BytecodeSourceMap,
    ConstantId,
    ConstantPool,
    FunctionTable,
    FunctionTableEntry,
    InstructionIndex,
    InstructionSourceMapEntry,
    PushConstant,
    Return,
    TraceExpression,
)
from kiwi.dsl.bytecode_codec import (
    BYTECODE_ENCODING_VERSION,
    BYTECODE_FORMAT_MAGIC,
    BytecodeDecodeCode,
    BytecodeDecodeFailure,
    decode_bytecode,
    encode_bytecode,
)
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.ids import DefinitionId, ExpressionId, FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import BooleanValue, IntegerValue, UnitValue
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId, SourceSpan
from kiwi.dsl.types import BuiltinType, FunctionType, NamedType


def test_bytecode_codec_round_trips_canonically() -> None:
    source = SourceFile(
        SourceFileId("codec.dtr"),
        "fn identity(x: Int) -> Int = let value = x in -value\n"
        "policy choose(flag: Bool) -> Int = if flag then identity(1) else 2\n"
        "fn truth() -> Bool = true\n",
    )
    module = _compiled(source)
    repeated_module = _compiled(source)

    encoded = encode_bytecode(module)
    decoded = decode_bytecode(encoded)

    assert decoded == module
    assert encode_bytecode(repeated_module) == encoded
    assert encode_bytecode(decoded) == encoded


def test_bytecode_codec_preserves_unit_and_compound_types() -> None:
    source_file_id = SourceFileId("manual.dtr")
    span = SourceSpan(source_file_id, ByteOffset(0), ByteOffset(0))
    function_id = FunctionId(0)
    instructions = (
        TraceExpression(ExpressionId(0)),
        PushConstant(ConstantId(0)),
        Return(),
    )
    module = BytecodeModule(
        BytecodeHeader(source_file_id),
        ConstantPool((UnitValue(), BooleanValue(True), IntegerValue(-7))),
        FunctionTable((FunctionTableEntry(function_id, DefinitionId(0), "unit", 0),)),
        (
            BytecodeFunction(
                function_id,
                DefinitionId(0),
                "unit",
                0,
                0,
                FunctionType((NamedType("Input"),), BuiltinType.UNIT),
                instructions,
            ),
        ),
        BytecodeSourceMap(
            tuple(
                InstructionSourceMapEntry(
                    function_id,
                    InstructionIndex(index),
                    ExpressionId(0),
                    span,
                )
                for index in range(len(instructions))
            )
        ),
    )

    decoded = decode_bytecode(encode_bytecode(module))

    assert decoded == module


def test_bytecode_codec_round_trips_version_two_strings_and_exact_quantities() -> None:
    source = SourceFile(
        SourceFileId("literals-codec.dtr"),
        'fn label() -> String = "alpha"\n'
        "fn wait() -> Duration = 250ms\n"
        "fn aim() -> Angle = 45deg\n"
        "fn chance() -> Probability = 70%\n"
        "fn range() -> Distance = 8m\n",
    )
    module = _compiled(source)

    decoded = decode_bytecode(encode_bytecode(module))

    assert decoded == module
    assert decoded.header.bytecode_version == 2


def test_bytecode_codec_decodes_legacy_version_one_without_reinterpretation() -> None:
    source = SourceFile(SourceFileId("legacy.dtr"), "fn value() -> Int = 1")
    checked = check(resolve(parse(lex(source)).module))
    assert checked.module is not None
    legacy_header = BytecodeHeader(
        source.file_id,
        LEGACY_SOURCE_LANGUAGE_VERSION,
        LEGACY_CORE_IR_VERSION,
        LEGACY_BYTECODE_VERSION,
    )
    module = compile_core(lower(checked.module).module, legacy_header)

    decoded = decode_bytecode(encode_bytecode(module))

    assert decoded == module
    assert decoded.header == legacy_header


def test_bytecode_codec_returns_structured_malformed_input_failures() -> None:
    module = _compiled(SourceFile(SourceFileId("codec.dtr"), "fn value() -> Int = 1"))
    encoded = encode_bytecode(module)
    invalid_utf8 = bytearray(encoded)
    source_offset = len(BYTECODE_FORMAT_MAGIC) + 1 + 4
    invalid_utf8[source_offset] = 0xFF
    noncanonical_integer = bytearray(encoded)
    integer_offset = len(BYTECODE_FORMAT_MAGIC) + 1 + 4 + len(module.header.source_file_id.value)
    integer_offset += 12 + 4
    noncanonical_integer[integer_offset + 6] = 0

    failures = (
        decode_bytecode(b""),
        decode_bytecode(encoded[:-1]),
        decode_bytecode(encoded + b"\x00"),
        decode_bytecode(bytes(invalid_utf8)),
        decode_bytecode(bytes(noncanonical_integer)),
        decode_bytecode(_unknown_opcode_module()),
        decode_bytecode(_validator_rejected_module()),
    )

    assert tuple(
        failure.code for failure in failures if isinstance(failure, BytecodeDecodeFailure)
    ) == (
        BytecodeDecodeCode.INVALID_MAGIC,
        BytecodeDecodeCode.TRUNCATED,
        BytecodeDecodeCode.TRAILING_BYTES,
        BytecodeDecodeCode.INVALID_UTF8,
        BytecodeDecodeCode.INVALID_VALUE,
        BytecodeDecodeCode.INVALID_OPCODE,
        BytecodeDecodeCode.INVALID_BYTECODE,
    )


@pytest.mark.parametrize("opcode", (b"\x0b", b"\x0d", b"\x0e", b"\x0f", b"\x10", b"\x11", b"\x12"))
def test_bytecode_codec_rejects_version_two_data_opcodes_in_legacy_modules(
    opcode: bytes,
) -> None:
    decoded = decode_bytecode(_single_instruction_module(opcode, b""))

    assert isinstance(decoded, BytecodeDecodeFailure)
    assert decoded.code is BytecodeDecodeCode.INVALID_OPCODE


def _unknown_opcode_module() -> bytes:
    return _single_instruction_module(b"\xff", b"")


def _validator_rejected_module() -> bytes:
    source_map = _u32(1) + _u32(0) + _u32(0) + _u32(0) + _u32(0) + _u32(0)
    return _single_instruction_module(b"\x09", source_map)


def _single_instruction_module(instruction: bytes, suffix: bytes) -> bytes:
    return b"".join(
        (
            BYTECODE_FORMAT_MAGIC,
            bytes((BYTECODE_ENCODING_VERSION,)),
            _u32(1),
            b"x",
            _u32(1),
            _u32(1),
            _u32(1),
            _u32(0),
            _u32(1),
            _u32(0),
            _u32(0),
            _u32(1),
            b"f",
            _u32(0),
            _u32(1),
            _u32(0),
            _u32(0),
            _u32(1),
            b"f",
            _u32(0),
            _u32(0),
            b"\x01",
            _u32(1),
            instruction,
            suffix,
        )
    )


def _u32(value: int) -> bytes:
    return value.to_bytes(4, "big")


def _compiled(source: SourceFile) -> BytecodeModule:
    checked = check(resolve(parse(lex(source)).module))
    assert checked.module is not None
    return compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
