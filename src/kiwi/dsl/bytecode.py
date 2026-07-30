"""Versioned bytecode module metadata for the Kiwi DSL."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from enum import IntEnum
from typing import ClassVar

from kiwi.dsl.core_ir import CoreDefinition
from kiwi.dsl.ids import DefinitionId, ExpressionId, FunctionId
from kiwi.dsl.runtime_values import BooleanValue, IntegerValue, UnitValue
from kiwi.dsl.source import SourceFileId
from kiwi.dsl.types import DslType

SOURCE_LANGUAGE_VERSION = 1
CORE_IR_VERSION = 1
BYTECODE_VERSION = 1


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
    """The initial encoded instruction tags for bytecode version 1."""

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
    | Jump
    | JumpIfFalse
    | Return
    | TraceExpression
)


type RuntimeConstant = IntegerValue | BooleanValue | UnitValue


@dataclass(frozen=True, slots=True)
class ConstantPool:
    """Unique runtime constants in first-explicit-encounter order."""

    values: tuple[RuntimeConstant, ...]

    def __post_init__(self) -> None:
        seen: list[RuntimeConstant] = []
        for value in self.values:
            if not isinstance(value, (IntegerValue, BooleanValue, UnitValue)):
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
        if not isinstance(value, (IntegerValue, BooleanValue, UnitValue)):
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
class BytecodeModule:
    """A compiled module before byte-level encoding is introduced."""

    header: BytecodeHeader
    constants: ConstantPool
    function_table: FunctionTable
    functions: tuple[BytecodeFunction, ...]

    def __post_init__(self) -> None:
        table_ids = tuple(entry.function_id for entry in self.function_table.entries)
        function_ids = tuple(function.function_id for function in self.functions)
        if function_ids != table_ids:
            raise ValueError("bytecode functions must match function-table order")


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
        _require_current_version(
            self.source_language_version,
            SOURCE_LANGUAGE_VERSION,
            "source language",
        )
        _require_current_version(self.core_ir_version, CORE_IR_VERSION, "core IR")
        _require_current_version(self.bytecode_version, BYTECODE_VERSION, "bytecode")


def _require_current_version(value: int, expected: int, name: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError(f"{name} version must be an integer")
    if value != expected:
        raise ValueError(f"unsupported {name} version {value}")
