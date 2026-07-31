"""Versioned bytecode module metadata for the Kiwi DSL."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from enum import IntEnum
from typing import ClassVar

from kiwi.dsl.core_ir import CoreDefinition
from kiwi.dsl.ids import DefinitionId, ExpressionId, FunctionId
from kiwi.dsl.intrinsics import IntrinsicKind
from kiwi.dsl.operators import BinaryOperator
from kiwi.dsl.runtime_values import (
    MAX_RUNTIME_CLOSURE_CAPTURES,
    MAX_RUNTIME_LIST_ITEMS,
    BooleanValue,
    IntegerValue,
    QuantityValue,
    StringValue,
    UnitValue,
)
from kiwi.dsl.source import SourceFileId, SourceSpan
from kiwi.dsl.types import BuiltinType, DslType, FunctionType, ListType, OptionType

LEGACY_SOURCE_LANGUAGE_VERSION = 1
LEGACY_CORE_IR_VERSION = 1
LEGACY_BYTECODE_VERSION = 1
SOURCE_LANGUAGE_VERSION = 2
CORE_IR_VERSION = 2
BYTECODE_VERSION = 2
_SUPPORTED_VERSION_TRIPLES = frozenset(
    {
        (
            LEGACY_SOURCE_LANGUAGE_VERSION,
            LEGACY_CORE_IR_VERSION,
            LEGACY_BYTECODE_VERSION,
        ),
        (SOURCE_LANGUAGE_VERSION, CORE_IR_VERSION, BYTECODE_VERSION),
    }
)


@dataclass(frozen=True, slots=True)
class ConstantId:
    """The canonical index of one module constant."""

    value: int

    def __post_init__(self) -> None:
        if not isinstance(self.value, int) or isinstance(self.value, bool) or self.value < 0:
            raise ValueError("constant ID must be a non-negative integer")


@dataclass(frozen=True, slots=True)
class LocalSlot:
    """One function-frame local slot index."""

    value: int

    def __post_init__(self) -> None:
        if not isinstance(self.value, int) or isinstance(self.value, bool) or self.value < 0:
            raise ValueError("local slot must be a non-negative integer")


@dataclass(frozen=True, slots=True)
class InstructionIndex:
    """An index into a function's instruction tuple."""

    value: int

    def __post_init__(self) -> None:
        if not isinstance(self.value, int) or isinstance(self.value, bool) or self.value < 0:
            raise ValueError("instruction index must be a non-negative integer")


class Opcode(IntEnum):
    """The fixed encoded instruction tags through bytecode version 2."""

    PUSH_CONSTANT = 1
    PUSH_FUNCTION = 2
    LOAD_LOCAL = 3
    STORE_LOCAL = 4
    NEGATE = 5
    CALL = 6
    JUMP = 7
    JUMP_IF_FALSE = 8
    RETURN = 9
    TRACE_EXPRESSION = 10
    BUILD_RECORD = 11
    LOAD_FIELD = 12
    BUILD_SOME = 13
    PUSH_NONE = 14
    JUMP_IF_NONE = 15
    UNWRAP_SOME = 16
    POP = 17
    BUILD_LIST = 18
    BUILD_CLOSURE = 19
    PUSH_INTRINSIC = 20
    BINARY_OPERATION = 21


@dataclass(frozen=True, slots=True)
class PushConstant:
    """Push one interned constant onto the value stack."""

    constant_id: ConstantId
    opcode: ClassVar[Opcode] = Opcode.PUSH_CONSTANT


@dataclass(frozen=True, slots=True)
class PushFunction:
    """Push an immutable function-table reference onto the value stack."""

    function_id: FunctionId
    opcode: ClassVar[Opcode] = Opcode.PUSH_FUNCTION


@dataclass(frozen=True, slots=True)
class LoadLocal:
    """Push a value from the active function frame."""

    slot: LocalSlot
    opcode: ClassVar[Opcode] = Opcode.LOAD_LOCAL


@dataclass(frozen=True, slots=True)
class StoreLocal:
    """Pop a value from the stack and write it to the active function frame."""

    slot: LocalSlot
    opcode: ClassVar[Opcode] = Opcode.STORE_LOCAL


@dataclass(frozen=True, slots=True)
class Negate:
    """Pop an integer and push its exact arithmetic negation."""

    opcode: ClassVar[Opcode] = Opcode.NEGATE


@dataclass(frozen=True, slots=True)
class Call:
    """Call a stack function value with the following argument count."""

    argument_count: int
    opcode: ClassVar[Opcode] = Opcode.CALL

    def __post_init__(self) -> None:
        if (
            not isinstance(self.argument_count, int)
            or isinstance(self.argument_count, bool)
            or self.argument_count < 0
        ):
            raise ValueError("call argument count must be a non-negative integer")


@dataclass(frozen=True, slots=True)
class BuildRecord:
    """Build one immutable record from source-ordered stack values."""

    type_name: str
    field_names: tuple[str, ...]
    opcode: ClassVar[Opcode] = Opcode.BUILD_RECORD

    def __post_init__(self) -> None:
        if not isinstance(self.type_name, str) or not self.type_name:
            raise ValueError("record type name must be a non-empty string")
        if any(not isinstance(name, str) or not name for name in self.field_names):
            raise ValueError("record field names must be non-empty strings")
        if len(set(self.field_names)) != len(self.field_names):
            raise ValueError("record field names must be unique")


@dataclass(frozen=True, slots=True)
class LoadField:
    """Pop a record and push one statically named field value."""

    field_name: str
    opcode: ClassVar[Opcode] = Opcode.LOAD_FIELD

    def __post_init__(self) -> None:
        if not isinstance(self.field_name, str) or not self.field_name:
            raise ValueError("record field name must be a non-empty string")


@dataclass(frozen=True, slots=True)
class BuildSome:
    """Wrap the top stack value in a payload-bearing `Option`."""

    opcode: ClassVar[Opcode] = Opcode.BUILD_SOME


@dataclass(frozen=True, slots=True)
class PushNone:
    """Push a payload-free `Option`."""

    opcode: ClassVar[Opcode] = Opcode.PUSH_NONE


@dataclass(frozen=True, slots=True)
class JumpIfNone:
    """Branch when the top stack value is `None` without consuming it."""

    target: InstructionIndex
    opcode: ClassVar[Opcode] = Opcode.JUMP_IF_NONE


@dataclass(frozen=True, slots=True)
class UnwrapSome:
    """Replace a payload-bearing `Option` with its value."""

    opcode: ClassVar[Opcode] = Opcode.UNWRAP_SOME


@dataclass(frozen=True, slots=True)
class Pop:
    """Discard the top stack value."""

    opcode: ClassVar[Opcode] = Opcode.POP


@dataclass(frozen=True, slots=True)
class BuildList:
    """Build one immutable list from source-ordered stack values."""

    element_count: int
    opcode: ClassVar[Opcode] = Opcode.BUILD_LIST

    def __post_init__(self) -> None:
        if (
            not isinstance(self.element_count, int)
            or isinstance(self.element_count, bool)
            or not 0 <= self.element_count <= MAX_RUNTIME_LIST_ITEMS
        ):
            raise ValueError("list element count exceeds the configured item limit")


@dataclass(frozen=True, slots=True)
class BuildClosure:
    """Build a callable closure from source-ordered captured stack values."""

    function_id: FunctionId
    capture_count: int
    opcode: ClassVar[Opcode] = Opcode.BUILD_CLOSURE

    def __post_init__(self) -> None:
        if not isinstance(self.function_id, FunctionId):
            raise ValueError("closure function ID must be a function ID")
        if (
            not isinstance(self.capture_count, int)
            or isinstance(self.capture_count, bool)
            or not 0 <= self.capture_count <= MAX_RUNTIME_CLOSURE_CAPTURES
        ):
            raise ValueError("closure capture count exceeds the configured capture limit")


@dataclass(frozen=True, slots=True)
class PushIntrinsic:
    """Push one closed standard-library intrinsic reference."""

    intrinsic: IntrinsicKind
    opcode: ClassVar[Opcode] = Opcode.PUSH_INTRINSIC

    def __post_init__(self) -> None:
        if not isinstance(self.intrinsic, IntrinsicKind):
            raise ValueError("intrinsic instruction requires an intrinsic kind")


@dataclass(frozen=True, slots=True)
class BinaryOperation:
    """Apply one closed exact domain operator to two stack values."""

    operator: BinaryOperator
    opcode: ClassVar[Opcode] = Opcode.BINARY_OPERATION

    def __post_init__(self) -> None:
        if not isinstance(self.operator, BinaryOperator):
            raise ValueError("binary instruction requires a binary operator")


@dataclass(frozen=True, slots=True)
class Jump:
    """Transfer control unconditionally to an instruction index."""

    target: InstructionIndex
    opcode: ClassVar[Opcode] = Opcode.JUMP


@dataclass(frozen=True, slots=True)
class JumpIfFalse:
    """Pop a boolean and branch when its value is false."""

    target: InstructionIndex
    opcode: ClassVar[Opcode] = Opcode.JUMP_IF_FALSE


@dataclass(frozen=True, slots=True)
class Return:
    """Return the top stack value from the active function frame."""

    opcode: ClassVar[Opcode] = Opcode.RETURN


@dataclass(frozen=True, slots=True)
class TraceExpression:
    """Retain the current source expression ID for deterministic tracing."""

    expression_id: ExpressionId
    opcode: ClassVar[Opcode] = Opcode.TRACE_EXPRESSION


type BytecodeInstruction = (
    PushConstant
    | PushFunction
    | LoadLocal
    | StoreLocal
    | Negate
    | Call
    | BuildRecord
    | LoadField
    | BuildSome
    | PushNone
    | JumpIfNone
    | UnwrapSome
    | Pop
    | BuildList
    | BuildClosure
    | PushIntrinsic
    | BinaryOperation
    | Jump
    | JumpIfFalse
    | Return
    | TraceExpression
)


type RuntimeConstant = IntegerValue | BooleanValue | UnitValue | StringValue | QuantityValue


@dataclass(frozen=True, slots=True)
class ConstantPool:
    """Unique runtime constants in first-explicit-encounter order."""

    values: tuple[RuntimeConstant, ...]

    def __post_init__(self) -> None:
        seen: list[RuntimeConstant] = []
        for value in self.values:
            if not isinstance(
                value,
                (IntegerValue, BooleanValue, UnitValue, StringValue, QuantityValue),
            ):
                raise ValueError("constant pool values must be runtime constants")
            if value in seen:
                raise ValueError("constant pool values must be unique")
            seen.append(value)

    def index_of(self, value: RuntimeConstant) -> ConstantId:
        """Return the canonical ID of one interned constant."""
        for index, candidate in enumerate(self.values):
            if candidate == value:
                return ConstantId(index)
        raise ValueError("constant is not interned")


class ConstantPoolBuilder:
    """Intern constants in the compiler's explicitly ordered traversal."""

    def __init__(self) -> None:
        self._values: list[RuntimeConstant] = []

    def intern(self, value: RuntimeConstant) -> ConstantId:
        """Return an existing or newly allocated canonical constant ID."""
        for index, candidate in enumerate(self._values):
            if candidate == value:
                return ConstantId(index)
        if not isinstance(
            value,
            (IntegerValue, BooleanValue, UnitValue, StringValue, QuantityValue),
        ):
            raise ValueError("constant pool values must be runtime constants")
        self._values.append(value)
        return ConstantId(len(self._values) - 1)

    def freeze(self) -> ConstantPool:
        """Return the immutable pool assembled so far."""
        return ConstantPool(tuple(self._values))


@dataclass(frozen=True, slots=True)
class FunctionTableEntry:
    """One core definition's canonical bytecode function-table position."""

    function_id: FunctionId
    definition_id: DefinitionId
    name: str
    arity: int

    def __post_init__(self) -> None:
        if self.arity < 0:
            raise ValueError("function arity must not be negative")


@dataclass(frozen=True, slots=True)
class FunctionTable:
    """Functions ordered by ascending source-assigned definition ID."""

    entries: tuple[FunctionTableEntry, ...]

    def __post_init__(self) -> None:
        expected_function_ids = tuple(range(len(self.entries)))
        function_ids = tuple(entry.function_id.value for entry in self.entries)
        definition_ids = tuple(entry.definition_id.value for entry in self.entries)
        if function_ids != expected_function_ids:
            raise ValueError("function IDs must be contiguous and ordered")
        if definition_ids != tuple(sorted(definition_ids)) or len(set(definition_ids)) != len(
            definition_ids
        ):
            raise ValueError("definition IDs must be unique and ordered")

    def function_id_for(self, definition_id: DefinitionId) -> FunctionId:
        """Return the function-table ID for one core definition."""
        for entry in self.entries:
            if entry.definition_id == definition_id:
                return entry.function_id
        raise ValueError("definition has no bytecode function")


@dataclass(frozen=True, slots=True)
class BytecodeFunction:
    """One compiled function with ordered instructions and local-frame metadata."""

    function_id: FunctionId
    definition_id: DefinitionId
    name: str
    arity: int
    local_slot_count: int
    return_type: DslType
    instructions: tuple[BytecodeInstruction, ...]

    def __post_init__(self) -> None:
        if self.arity < 0 or self.local_slot_count < self.arity:
            raise ValueError("function local slots must include all parameters")


@dataclass(frozen=True, slots=True)
class InstructionSourceMapEntry:
    """One bytecode instruction's source expression and span provenance."""

    function_id: FunctionId
    instruction_index: InstructionIndex
    expression_id: ExpressionId
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class BytecodeSourceMap:
    """Canonical instruction-to-expression source provenance for one module."""

    entries: tuple[InstructionSourceMapEntry, ...]

    def entry_for(
        self,
        function_id: FunctionId,
        instruction_index: InstructionIndex,
    ) -> InstructionSourceMapEntry:
        """Return the source provenance for one valid bytecode instruction."""
        for entry in self.entries:
            if entry.function_id == function_id and entry.instruction_index == instruction_index:
                return entry
        raise ValueError("bytecode instruction has no source-map entry")


@dataclass(frozen=True, slots=True)
class BytecodeModule:
    """A compiled module before byte-level encoding is introduced."""

    header: BytecodeHeader
    constants: ConstantPool
    function_table: FunctionTable
    functions: tuple[BytecodeFunction, ...]
    source_map: BytecodeSourceMap

    def __post_init__(self) -> None:
        table_ids = tuple(entry.function_id for entry in self.function_table.entries)
        function_ids = tuple(function.function_id for function in self.functions)
        if function_ids != table_ids:
            raise ValueError("bytecode functions must match function-table order")
        expected_locations = tuple(
            (function.function_id, InstructionIndex(index))
            for function in self.functions
            for index, _ in enumerate(function.instructions)
        )
        actual_locations = tuple(
            (entry.function_id, entry.instruction_index) for entry in self.source_map.entries
        )
        if actual_locations != expected_locations:
            raise ValueError("bytecode source map must cover instructions in canonical order")
        if any(
            entry.span.file_id != self.header.source_file_id for entry in self.source_map.entries
        ):
            raise ValueError("bytecode source map spans must match header source file")
        if self.header.bytecode_version == LEGACY_BYTECODE_VERSION and (
            any(isinstance(value, (StringValue, QuantityValue)) for value in self.constants.values)
            or any(_uses_version_two_type(function.return_type) for function in self.functions)
            or any(
                isinstance(
                    instruction,
                    (
                        BuildRecord,
                        LoadField,
                        BuildSome,
                        PushNone,
                        JumpIfNone,
                        UnwrapSome,
                        Pop,
                        BuildList,
                        BuildClosure,
                        PushIntrinsic,
                        BinaryOperation,
                    ),
                )
                for function in self.functions
                for instruction in function.instructions
            )
        ):
            raise ValueError("bytecode version 1 does not support version 2 values or types")


def canonical_function_table(definitions: Sequence[CoreDefinition]) -> FunctionTable:
    """Assign function IDs after explicit ascending `DefinitionId` ordering."""
    ordered_definitions = sorted(definitions, key=lambda definition: definition.definition_id.value)
    return FunctionTable(
        tuple(
            FunctionTableEntry(
                FunctionId(index),
                definition.definition_id,
                definition.name,
                len(definition.parameters),
            )
            for index, definition in enumerate(ordered_definitions)
        )
    )


@dataclass(frozen=True, slots=True)
class BytecodeHeader:
    """Compatibility metadata required by every compiled bytecode module."""

    source_file_id: SourceFileId
    source_language_version: int = SOURCE_LANGUAGE_VERSION
    core_ir_version: int = CORE_IR_VERSION
    bytecode_version: int = BYTECODE_VERSION

    def __post_init__(self) -> None:
        versions = (
            self.source_language_version,
            self.core_ir_version,
            self.bytecode_version,
        )
        if any(not isinstance(value, int) or isinstance(value, bool) for value in versions):
            raise ValueError("bytecode compatibility versions must be integers")
        if versions not in _SUPPORTED_VERSION_TRIPLES:
            raise ValueError(f"unsupported bytecode compatibility triple {versions}")


def _uses_version_two_type(type_: DslType) -> bool:
    if isinstance(type_, BuiltinType):
        return type_ in {
            BuiltinType.STRING,
            BuiltinType.DURATION,
            BuiltinType.DISTANCE,
            BuiltinType.ANGLE,
            BuiltinType.PROBABILITY,
        }
    if isinstance(type_, OptionType):
        return True
    if isinstance(type_, ListType):
        return True
    return isinstance(type_, FunctionType) and (
        any(_uses_version_two_type(parameter) for parameter in type_.parameters)
        or _uses_version_two_type(type_.return_type)
    )
