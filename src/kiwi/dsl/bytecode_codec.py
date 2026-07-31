"""Canonical bounded binary encoding for Kiwi bytecode modules."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.dsl.bytecode import (
    BYTECODE_VERSION,
    BinaryOperation,
    BuildClosure,
    BuildList,
    BuildRecord,
    BuildSome,
    BytecodeFunction,
    BytecodeHeader,
    BytecodeInstruction,
    BytecodeModule,
    BytecodeSourceMap,
    Call,
    ConstantId,
    ConstantPool,
    FunctionTable,
    FunctionTableEntry,
    InstructionIndex,
    InstructionSourceMapEntry,
    Jump,
    JumpIfFalse,
    JumpIfNone,
    LoadField,
    LoadLocal,
    LocalSlot,
    Negate,
    Opcode,
    Pop,
    PushConstant,
    PushFunction,
    PushIntrinsic,
    PushNone,
    Return,
    StoreLocal,
    TraceExpression,
    UnwrapSome,
)
from kiwi.dsl.ids import DefinitionId, ExpressionId, FunctionId
from kiwi.dsl.intrinsics import IntrinsicKind
from kiwi.dsl.operators import BinaryOperator
from kiwi.dsl.runtime_values import (
    BooleanValue,
    IntegerValue,
    QuantityValue,
    StringValue,
    UnitValue,
)
from kiwi.dsl.source import ByteOffset, SourceFileId, SourceSpan
from kiwi.dsl.types import BuiltinType, DslType, FunctionType, ListType, NamedType, OptionType
from kiwi.dsl.validator import BytecodeValidationError, validate_bytecode

BYTECODE_FORMAT_MAGIC = b"KWI-BC\x00"
BYTECODE_ENCODING_VERSION = 1
MAX_ENCODED_BYTECODE_BYTES = 16 * 1_024 * 1_024
MAX_COLLECTION_ITEMS = 65_536
MAX_TEXT_BYTES = 65_536
MAX_INTEGER_BYTES = 512
MAX_TYPE_DEPTH = 64
_MAX_U32 = (1 << 32) - 1

_INTEGER_CONSTANT = 1
_BOOLEAN_CONSTANT = 2
_UNIT_CONSTANT = 3
_STRING_CONSTANT = 4
_QUANTITY_CONSTANT = 5
_DURATION_DIMENSION = 1
_DISTANCE_DIMENSION = 2
_ANGLE_DIMENSION = 3
_PROBABILITY_DIMENSION = 4
_TYPE_INT = 1
_TYPE_BOOL = 2
_TYPE_UNIT = 3
_TYPE_NAMED = 4
_TYPE_FUNCTION = 5
_TYPE_STRING = 6
_TYPE_DURATION = 7
_TYPE_DISTANCE = 8
_TYPE_ANGLE = 9
_TYPE_PROBABILITY = 10
_TYPE_OPTION = 11
_TYPE_LIST = 12


class BytecodeDecodeCode(StrEnum):
    """Stable failures returned by the bytecode decoder."""

    INVALID_MAGIC = "C001_INVALID_MAGIC"
    UNSUPPORTED_ENCODING_VERSION = "C002_UNSUPPORTED_ENCODING_VERSION"
    TOO_LARGE = "C003_TOO_LARGE"
    TRUNCATED = "C004_TRUNCATED"
    INVALID_UTF8 = "C005_INVALID_UTF8"
    INVALID_VALUE = "C006_INVALID_VALUE"
    INVALID_OPCODE = "C007_INVALID_OPCODE"
    TRAILING_BYTES = "C008_TRAILING_BYTES"
    INVALID_MODULE = "C009_INVALID_MODULE"
    INVALID_BYTECODE = "C010_INVALID_BYTECODE"


@dataclass(frozen=True, slots=True)
class BytecodeDecodeFailure:
    """One structured binary-bytecode decoding failure."""

    code: BytecodeDecodeCode
    offset: int
    message: str
    validation_errors: tuple[BytecodeValidationError, ...] = ()


type BytecodeDecodeResult = BytecodeModule | BytecodeDecodeFailure


def encode_bytecode(module: BytecodeModule) -> bytes:
    """Encode one validator-clean module in canonical binary form."""
    validation = validate_bytecode(module)
    if not validation.is_valid:
        raise ValueError("cannot encode bytecode rejected by the validator")
    writer = _Writer()
    writer.write(BYTECODE_FORMAT_MAGIC)
    writer.u8(BYTECODE_ENCODING_VERSION, "encoding version")
    _encode_header(writer, module.header)
    writer.items(len(module.constants.values), "constant count")
    for constant in module.constants.values:
        _encode_constant(writer, constant)
    writer.items(len(module.function_table.entries), "function-table count")
    for entry in module.function_table.entries:
        _encode_function_table_entry(writer, entry)
    writer.items(len(module.functions), "function count")
    for function in module.functions:
        _encode_function(writer, function)
    writer.items(len(module.source_map.entries), "source-map entry count")
    for source_entry in module.source_map.entries:
        _encode_source_map_entry(writer, source_entry)
    encoded = bytes(writer.data)
    if len(encoded) > MAX_ENCODED_BYTECODE_BYTES:
        raise ValueError("encoded bytecode exceeds the configured byte limit")
    return encoded


def decode_bytecode(data: bytes) -> BytecodeDecodeResult:
    """Decode one bounded binary module without executing it."""
    if not isinstance(data, bytes):
        raise TypeError("bytecode data must be bytes")
    if len(data) > MAX_ENCODED_BYTECODE_BYTES:
        return BytecodeDecodeFailure(
            BytecodeDecodeCode.TOO_LARGE,
            0,
            "bytecode exceeds the configured byte limit",
        )
    if len(data) < len(BYTECODE_FORMAT_MAGIC) or not data.startswith(BYTECODE_FORMAT_MAGIC):
        return BytecodeDecodeFailure(
            BytecodeDecodeCode.INVALID_MAGIC,
            0,
            "bytecode format identifier is invalid",
        )
    reader = _Reader(data, len(BYTECODE_FORMAT_MAGIC))
    try:
        version = reader.u8()
        if version != BYTECODE_ENCODING_VERSION:
            raise _DecodeError(
                BytecodeDecodeCode.UNSUPPORTED_ENCODING_VERSION,
                reader.offset - 1,
                f"unsupported bytecode encoding version {version}",
            )
        module = _decode_module(reader)
        if reader.remaining:
            raise _DecodeError(
                BytecodeDecodeCode.TRAILING_BYTES,
                reader.offset,
                "bytecode contains trailing bytes",
            )
    except _DecodeError as error:
        return BytecodeDecodeFailure(error.code, error.offset, error.message)
    except (TypeError, ValueError):
        return BytecodeDecodeFailure(
            BytecodeDecodeCode.INVALID_MODULE,
            reader.offset,
            "bytecode fields do not form a valid module",
        )
    validation = validate_bytecode(module)
    if not validation.is_valid:
        return BytecodeDecodeFailure(
            BytecodeDecodeCode.INVALID_BYTECODE,
            reader.offset,
            "decoded bytecode failed validation",
            validation.errors,
        )
    return module


def _encode_header(writer: _Writer, header: BytecodeHeader) -> None:
    writer.text(header.source_file_id.value)
    writer.u32(header.source_language_version, "source language version")
    writer.u32(header.core_ir_version, "core IR version")
    writer.u32(header.bytecode_version, "bytecode version")


def _encode_constant(
    writer: _Writer,
    constant: IntegerValue | BooleanValue | UnitValue | StringValue | QuantityValue,
) -> None:
    if isinstance(constant, IntegerValue):
        writer.u8(_INTEGER_CONSTANT, "constant tag")
        _encode_integer(writer, constant.value)
    elif isinstance(constant, BooleanValue):
        writer.u8(_BOOLEAN_CONSTANT, "constant tag")
        writer.u8(int(constant.value), "boolean value")
    elif isinstance(constant, UnitValue):
        writer.u8(_UNIT_CONSTANT, "constant tag")
    elif isinstance(constant, StringValue):
        writer.u8(_STRING_CONSTANT, "constant tag")
        writer.text(constant.value)
    elif isinstance(constant, QuantityValue):
        writer.u8(_QUANTITY_CONSTANT, "constant tag")
        _encode_quantity(writer, constant.value)
    else:
        raise TypeError("constant pool contains an unsupported value")


def _encode_integer(writer: _Writer, value: int) -> None:
    if not isinstance(value, int) or isinstance(value, bool):
        raise TypeError("integer constant must be an integer")
    magnitude = abs(value)
    bytes_required = (magnitude.bit_length() + 7) // 8
    if bytes_required > MAX_INTEGER_BYTES:
        raise ValueError("integer constant exceeds the configured byte limit")
    writer.u8(1 if value < 0 else 0, "integer sign")
    writer.u32(bytes_required, "integer magnitude length")
    if bytes_required:
        writer.write(magnitude.to_bytes(bytes_required, "big"))


def _encode_quantity(writer: _Writer, quantity: Quantity) -> None:
    dimension_tag = {
        QuantityDimension.DURATION: _DURATION_DIMENSION,
        QuantityDimension.DISTANCE: _DISTANCE_DIMENSION,
        QuantityDimension.ANGLE: _ANGLE_DIMENSION,
        QuantityDimension.PROBABILITY: _PROBABILITY_DIMENSION,
    }[quantity.dimension]
    writer.u8(dimension_tag, "quantity dimension")
    _encode_integer(writer, quantity.value.numerator)
    _encode_natural(writer, quantity.value.denominator, "quantity denominator")


def _encode_natural(writer: _Writer, value: int, name: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise ValueError(f"{name} must be a positive integer")
    bytes_required = (value.bit_length() + 7) // 8
    if bytes_required > MAX_INTEGER_BYTES:
        raise ValueError(f"{name} exceeds the configured byte limit")
    writer.u32(bytes_required, f"{name} length")
    writer.write(value.to_bytes(bytes_required, "big"))


def _encode_function_table_entry(writer: _Writer, entry: FunctionTableEntry) -> None:
    writer.u32(entry.function_id.value, "function ID")
    writer.u32(entry.definition_id.value, "definition ID")
    writer.text(entry.name)
    writer.u32(entry.arity, "function arity")


def _encode_function(writer: _Writer, function: BytecodeFunction) -> None:
    writer.u32(function.function_id.value, "function ID")
    writer.u32(function.definition_id.value, "definition ID")
    writer.text(function.name)
    writer.u32(function.arity, "function arity")
    writer.u32(function.local_slot_count, "local-slot count")
    _encode_type(writer, function.return_type, 0)
    writer.items(len(function.instructions), "instruction count")
    for instruction in function.instructions:
        _encode_instruction(writer, instruction)


def _encode_type(writer: _Writer, type_: DslType, depth: int) -> None:
    if depth >= MAX_TYPE_DEPTH:
        raise ValueError("type exceeds the configured nesting limit")
    if type_ is BuiltinType.INT:
        writer.u8(_TYPE_INT, "type tag")
    elif type_ is BuiltinType.BOOL:
        writer.u8(_TYPE_BOOL, "type tag")
    elif type_ is BuiltinType.UNIT:
        writer.u8(_TYPE_UNIT, "type tag")
    elif type_ is BuiltinType.STRING:
        writer.u8(_TYPE_STRING, "type tag")
    elif type_ is BuiltinType.DURATION:
        writer.u8(_TYPE_DURATION, "type tag")
    elif type_ is BuiltinType.DISTANCE:
        writer.u8(_TYPE_DISTANCE, "type tag")
    elif type_ is BuiltinType.ANGLE:
        writer.u8(_TYPE_ANGLE, "type tag")
    elif type_ is BuiltinType.PROBABILITY:
        writer.u8(_TYPE_PROBABILITY, "type tag")
    elif isinstance(type_, NamedType):
        writer.u8(_TYPE_NAMED, "type tag")
        writer.text(type_.name)
    elif isinstance(type_, OptionType):
        writer.u8(_TYPE_OPTION, "type tag")
        _encode_type(writer, type_.element_type, depth + 1)
    elif isinstance(type_, ListType):
        writer.u8(_TYPE_LIST, "type tag")
        _encode_type(writer, type_.element_type, depth + 1)
    elif isinstance(type_, FunctionType):
        writer.u8(_TYPE_FUNCTION, "type tag")
        writer.items(len(type_.parameters), "function-type parameter count")
        for parameter in type_.parameters:
            _encode_type(writer, parameter, depth + 1)
        _encode_type(writer, type_.return_type, depth + 1)
    else:
        raise TypeError("bytecode function return type is not a DSL type")


def _encode_instruction(writer: _Writer, instruction: BytecodeInstruction) -> None:
    writer.u8(instruction.opcode.value, "opcode")
    if isinstance(instruction, PushConstant):
        writer.u32(instruction.constant_id.value, "constant ID")
    elif isinstance(instruction, PushFunction):
        writer.u32(instruction.function_id.value, "function ID")
    elif isinstance(instruction, PushIntrinsic):
        writer.u8(instruction.intrinsic.value, "intrinsic kind")
    elif isinstance(instruction, BinaryOperation):
        writer.u8(instruction.operator.value, "binary operator")
    elif isinstance(instruction, (LoadLocal, StoreLocal)):
        writer.u32(instruction.slot.value, "local slot")
    elif isinstance(instruction, Call):
        writer.u32(instruction.argument_count, "call argument count")
    elif isinstance(instruction, BuildList):
        writer.u32(instruction.element_count, "list element count")
    elif isinstance(instruction, BuildClosure):
        writer.u32(instruction.function_id.value, "closure function ID")
        writer.u32(instruction.capture_count, "closure capture count")
    elif isinstance(instruction, BuildRecord):
        writer.text(instruction.type_name)
        writer.items(len(instruction.field_names), "record field count")
        for field_name in instruction.field_names:
            writer.text(field_name)
    elif isinstance(instruction, LoadField):
        writer.text(instruction.field_name)
    elif isinstance(instruction, (Jump, JumpIfFalse, JumpIfNone)):
        writer.u32(instruction.target.value, "jump target")
    elif isinstance(instruction, TraceExpression):
        writer.u32(instruction.expression_id.value, "expression ID")


def _encode_source_map_entry(writer: _Writer, entry: InstructionSourceMapEntry) -> None:
    writer.u32(entry.function_id.value, "source-map function ID")
    writer.u32(entry.instruction_index.value, "source-map instruction index")
    writer.u32(entry.expression_id.value, "source-map expression ID")
    writer.u32(entry.span.start.value, "source-map span start")
    writer.u32(entry.span.end.value, "source-map span end")


def _decode_module(reader: _Reader) -> BytecodeModule:
    header = BytecodeHeader(
        SourceFileId(reader.text("source file ID")),
        reader.u32(),
        reader.u32(),
        reader.u32(),
    )
    constants = ConstantPool(
        tuple(
            _decode_constant(reader, header.bytecode_version)
            for _ in range(reader.items("constant count"))
        )
    )
    table = FunctionTable(
        tuple(
            FunctionTableEntry(
                FunctionId(reader.u32()),
                DefinitionId(reader.u32()),
                reader.text("function name"),
                reader.u32(),
            )
            for _ in range(reader.items("function-table count"))
        )
    )
    functions = tuple(
        _decode_function(reader, header.bytecode_version)
        for _ in range(reader.items("function count"))
    )
    source_map = BytecodeSourceMap(
        tuple(
            _decode_source_map_entry(reader, header.source_file_id)
            for _ in range(reader.items("source-map entry count"))
        )
    )
    return BytecodeModule(header, constants, table, functions, source_map)


def _decode_constant(
    reader: _Reader,
    bytecode_version: int,
) -> IntegerValue | BooleanValue | UnitValue | StringValue | QuantityValue:
    tag = reader.u8()
    if tag == _INTEGER_CONSTANT:
        return IntegerValue(_decode_integer(reader))
    if tag == _BOOLEAN_CONSTANT:
        value = reader.u8()
        if value not in (0, 1):
            raise _DecodeError(
                BytecodeDecodeCode.INVALID_VALUE,
                reader.offset - 1,
                "boolean constant must be zero or one",
            )
        return BooleanValue(bool(value))
    if tag == _UNIT_CONSTANT:
        return UnitValue()
    if bytecode_version == BYTECODE_VERSION and tag == _STRING_CONSTANT:
        return StringValue(reader.text("string constant"))
    if bytecode_version == BYTECODE_VERSION and tag == _QUANTITY_CONSTANT:
        return QuantityValue(_decode_quantity(reader))
    raise _DecodeError(
        BytecodeDecodeCode.INVALID_VALUE,
        reader.offset - 1,
        f"unknown constant tag {tag}",
    )


def _decode_integer(reader: _Reader) -> int:
    sign_offset = reader.offset
    sign = reader.u8()
    if sign not in (0, 1):
        raise _DecodeError(
            BytecodeDecodeCode.INVALID_VALUE,
            sign_offset,
            "integer sign must be zero or one",
        )
    length = reader.length(MAX_INTEGER_BYTES, "integer magnitude length")
    magnitude_bytes = reader.read(length)
    if not magnitude_bytes:
        if sign:
            raise _DecodeError(
                BytecodeDecodeCode.INVALID_VALUE,
                sign_offset,
                "zero integer must not have a negative sign",
            )
        return 0
    if magnitude_bytes[0] == 0:
        raise _DecodeError(
            BytecodeDecodeCode.INVALID_VALUE,
            reader.offset - length,
            "integer magnitude has a leading zero byte",
        )
    magnitude = int.from_bytes(magnitude_bytes, "big")
    return -magnitude if sign else magnitude


def _decode_quantity(reader: _Reader) -> Quantity:
    tag_offset = reader.offset
    dimension_tag = reader.u8()
    dimensions = {
        _DURATION_DIMENSION: QuantityDimension.DURATION,
        _DISTANCE_DIMENSION: QuantityDimension.DISTANCE,
        _ANGLE_DIMENSION: QuantityDimension.ANGLE,
        _PROBABILITY_DIMENSION: QuantityDimension.PROBABILITY,
    }
    dimension = dimensions.get(dimension_tag)
    if dimension is None:
        raise _DecodeError(
            BytecodeDecodeCode.INVALID_VALUE,
            tag_offset,
            f"unknown quantity dimension {dimension_tag}",
        )
    return Quantity(dimension, ExactRational(_decode_integer(reader), _decode_natural(reader)))


def _decode_natural(reader: _Reader) -> int:
    length = reader.length(MAX_INTEGER_BYTES, "quantity denominator length")
    value_offset = reader.offset
    encoded = reader.read(length)
    if not encoded or encoded[0] == 0:
        raise _DecodeError(
            BytecodeDecodeCode.INVALID_VALUE,
            value_offset,
            "quantity denominator has a non-canonical encoding",
        )
    return int.from_bytes(encoded, "big")


def _decode_function(reader: _Reader, bytecode_version: int) -> BytecodeFunction:
    return BytecodeFunction(
        FunctionId(reader.u32()),
        DefinitionId(reader.u32()),
        reader.text("function name"),
        reader.u32(),
        reader.u32(),
        _decode_type(reader, 0, bytecode_version),
        tuple(
            _decode_instruction(reader, bytecode_version)
            for _ in range(reader.items("instruction count"))
        ),
    )


def _decode_type(reader: _Reader, depth: int, bytecode_version: int) -> DslType:
    if depth >= MAX_TYPE_DEPTH:
        raise _DecodeError(
            BytecodeDecodeCode.INVALID_VALUE,
            reader.offset,
            "type exceeds the configured nesting limit",
        )
    tag_offset = reader.offset
    tag = reader.u8()
    if tag == _TYPE_INT:
        return BuiltinType.INT
    if tag == _TYPE_BOOL:
        return BuiltinType.BOOL
    if tag == _TYPE_UNIT:
        return BuiltinType.UNIT
    if bytecode_version == BYTECODE_VERSION:
        modern_builtin_types = {
            _TYPE_STRING: BuiltinType.STRING,
            _TYPE_DURATION: BuiltinType.DURATION,
            _TYPE_DISTANCE: BuiltinType.DISTANCE,
            _TYPE_ANGLE: BuiltinType.ANGLE,
            _TYPE_PROBABILITY: BuiltinType.PROBABILITY,
        }
        if builtin_type := modern_builtin_types.get(tag):
            return builtin_type
        if tag == _TYPE_OPTION:
            return OptionType(_decode_type(reader, depth + 1, bytecode_version))
        if tag == _TYPE_LIST:
            return ListType(_decode_type(reader, depth + 1, bytecode_version))
    if tag == _TYPE_NAMED:
        return NamedType(reader.text("named type"))
    if tag == _TYPE_FUNCTION:
        parameters = tuple(
            _decode_type(reader, depth + 1, bytecode_version)
            for _ in range(reader.items("function-type parameter count"))
        )
        return FunctionType(parameters, _decode_type(reader, depth + 1, bytecode_version))
    raise _DecodeError(
        BytecodeDecodeCode.INVALID_VALUE,
        tag_offset,
        f"unknown type tag {tag}",
    )


def _decode_instruction(reader: _Reader, bytecode_version: int) -> BytecodeInstruction:
    opcode_offset = reader.offset
    opcode_value = reader.u8()
    try:
        opcode = Opcode(opcode_value)
    except ValueError as error:
        raise _DecodeError(
            BytecodeDecodeCode.INVALID_OPCODE,
            opcode_offset,
            f"unknown opcode {opcode_value}",
        ) from error
    if bytecode_version != BYTECODE_VERSION and opcode in {
        Opcode.BUILD_RECORD,
        Opcode.LOAD_FIELD,
        Opcode.BUILD_SOME,
        Opcode.PUSH_NONE,
        Opcode.JUMP_IF_NONE,
        Opcode.UNWRAP_SOME,
        Opcode.POP,
        Opcode.BUILD_LIST,
        Opcode.BUILD_CLOSURE,
        Opcode.PUSH_INTRINSIC,
        Opcode.BINARY_OPERATION,
    }:
        raise _DecodeError(
            BytecodeDecodeCode.INVALID_OPCODE,
            opcode_offset,
            f"opcode {opcode_value} is not available in bytecode version {bytecode_version}",
        )
    if opcode is Opcode.PUSH_CONSTANT:
        return PushConstant(ConstantId(reader.u32()))
    if opcode is Opcode.PUSH_FUNCTION:
        return PushFunction(FunctionId(reader.u32()))
    if opcode is Opcode.PUSH_INTRINSIC:
        intrinsic_offset = reader.offset
        try:
            return PushIntrinsic(IntrinsicKind(reader.u8()))
        except ValueError as error:
            raise _DecodeError(
                BytecodeDecodeCode.INVALID_VALUE,
                intrinsic_offset,
                "unknown intrinsic kind",
            ) from error
    if opcode is Opcode.BINARY_OPERATION:
        operator_offset = reader.offset
        try:
            return BinaryOperation(BinaryOperator(reader.u8()))
        except ValueError as error:
            raise _DecodeError(
                BytecodeDecodeCode.INVALID_VALUE,
                operator_offset,
                "unknown binary operator",
            ) from error
    if opcode is Opcode.LOAD_LOCAL:
        return LoadLocal(LocalSlot(reader.u32()))
    if opcode is Opcode.STORE_LOCAL:
        return StoreLocal(LocalSlot(reader.u32()))
    if opcode is Opcode.NEGATE:
        return Negate()
    if opcode is Opcode.CALL:
        return Call(reader.u32())
    if opcode is Opcode.BUILD_LIST:
        return BuildList(reader.u32())
    if opcode is Opcode.BUILD_CLOSURE:
        return BuildClosure(FunctionId(reader.u32()), reader.u32())
    if opcode is Opcode.BUILD_RECORD:
        return BuildRecord(
            reader.text("record type name"),
            tuple(
                reader.text("record field name") for _ in range(reader.items("record field count"))
            ),
        )
    if opcode is Opcode.LOAD_FIELD:
        return LoadField(reader.text("record field name"))
    if opcode is Opcode.BUILD_SOME:
        return BuildSome()
    if opcode is Opcode.PUSH_NONE:
        return PushNone()
    if opcode is Opcode.JUMP_IF_NONE:
        return JumpIfNone(InstructionIndex(reader.u32()))
    if opcode is Opcode.UNWRAP_SOME:
        return UnwrapSome()
    if opcode is Opcode.POP:
        return Pop()
    if opcode is Opcode.JUMP:
        return Jump(InstructionIndex(reader.u32()))
    if opcode is Opcode.JUMP_IF_FALSE:
        return JumpIfFalse(InstructionIndex(reader.u32()))
    if opcode is Opcode.RETURN:
        return Return()
    if opcode is Opcode.TRACE_EXPRESSION:
        return TraceExpression(ExpressionId(reader.u32()))
    raise AssertionError("recognized opcode was not decoded")


def _decode_source_map_entry(
    reader: _Reader,
    source_file_id: SourceFileId,
) -> InstructionSourceMapEntry:
    return InstructionSourceMapEntry(
        FunctionId(reader.u32()),
        InstructionIndex(reader.u32()),
        ExpressionId(reader.u32()),
        SourceSpan(source_file_id, ByteOffset(reader.u32()), ByteOffset(reader.u32())),
    )


@dataclass(slots=True)
class _Writer:
    data: bytearray

    def __init__(self) -> None:
        self.data = bytearray()

    def write(self, value: bytes) -> None:
        self.data.extend(value)

    def u8(self, value: int, name: str) -> None:
        if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 0xFF:
            raise ValueError(f"{name} must fit in one byte")
        self.data.append(value)

    def u32(self, value: int, name: str) -> None:
        if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= _MAX_U32:
            raise ValueError(f"{name} must fit in an unsigned 32-bit integer")
        self.data.extend(value.to_bytes(4, "big"))

    def items(self, value: int, name: str) -> None:
        if not isinstance(value, int) or value < 0 or value > MAX_COLLECTION_ITEMS:
            raise ValueError(f"{name} exceeds the configured item limit")
        self.u32(value, name)

    def text(self, value: str) -> None:
        if not isinstance(value, str):
            raise TypeError("encoded text must be a string")
        encoded = value.encode("utf-8")
        if len(encoded) > MAX_TEXT_BYTES:
            raise ValueError("encoded text exceeds the configured byte limit")
        self.u32(len(encoded), "text length")
        self.write(encoded)


@dataclass(slots=True)
class _Reader:
    data: bytes
    offset: int

    @property
    def remaining(self) -> int:
        return len(self.data) - self.offset

    def read(self, length: int) -> bytes:
        if length > self.remaining:
            raise _DecodeError(
                BytecodeDecodeCode.TRUNCATED,
                self.offset,
                "bytecode ends before the declared value",
            )
        result = self.data[self.offset : self.offset + length]
        self.offset += length
        return result

    def u8(self) -> int:
        return self.read(1)[0]

    def u32(self) -> int:
        return int.from_bytes(self.read(4), "big")

    def items(self, name: str) -> int:
        return self.length(MAX_COLLECTION_ITEMS, name)

    def length(self, maximum: int, name: str) -> int:
        value = self.u32()
        if value > maximum:
            raise _DecodeError(
                BytecodeDecodeCode.INVALID_VALUE,
                self.offset - 4,
                f"{name} exceeds the configured limit",
            )
        return value

    def text(self, name: str) -> str:
        length = self.length(MAX_TEXT_BYTES, f"{name} length")
        try:
            return self.read(length).decode("utf-8")
        except UnicodeDecodeError as error:
            raise _DecodeError(
                BytecodeDecodeCode.INVALID_UTF8,
                self.offset - length + error.start,
                f"{name} is not valid UTF-8",
            ) from error


@dataclass(frozen=True, slots=True)
class _DecodeError(Exception):
    code: BytecodeDecodeCode
    offset: int
    message: str
