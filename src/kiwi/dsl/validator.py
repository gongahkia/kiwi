"""Structured validation for untrusted or decoded Kiwi bytecode."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.dsl.bytecode import (
    BuildRecord,
    BytecodeFunction,
    BytecodeInstruction,
    BytecodeModule,
    Call,
    ConstantId,
    InstructionIndex,
    Jump,
    JumpIfFalse,
    LoadField,
    LoadLocal,
    LocalSlot,
    Negate,
    PushConstant,
    PushFunction,
    Return,
    StoreLocal,
    TraceExpression,
)
from kiwi.dsl.ids import FunctionId


class BytecodeValidationCode(StrEnum):
    """Stable errors raised before the VM accepts a bytecode module."""

    FUNCTION_TABLE_MISMATCH = "B001_FUNCTION_TABLE_MISMATCH"
    EMPTY_FUNCTION = "B002_EMPTY_FUNCTION"
    INVALID_CONSTANT = "B003_INVALID_CONSTANT"
    INVALID_FUNCTION = "B004_INVALID_FUNCTION"
    INVALID_LOCAL_SLOT = "B005_INVALID_LOCAL_SLOT"
    INVALID_JUMP = "B006_INVALID_JUMP"
    INVALID_INSTRUCTION = "B007_INVALID_INSTRUCTION"
    STACK_UNDERFLOW = "B008_STACK_UNDERFLOW"
    CONTROL_FLOW_FALLTHROUGH = "B009_CONTROL_FLOW_FALLTHROUGH"
    INCONSISTENT_STACK_HEIGHT = "B010_INCONSISTENT_STACK_HEIGHT"
    RETURN_STACK_HEIGHT = "B011_RETURN_STACK_HEIGHT"


@dataclass(frozen=True, slots=True)
class BytecodeValidationError:
    """One deterministic bytecode rejection with its function and instruction."""

    code: BytecodeValidationCode
    message: str
    function_id: FunctionId | None = None
    instruction_index: InstructionIndex | None = None


@dataclass(frozen=True, slots=True)
class BytecodeValidationResult:
    """The complete ordered validation result for one module."""

    errors: tuple[BytecodeValidationError, ...]

    @property
    def is_valid(self) -> bool:
        """Return whether execution may begin."""
        return not self.errors


def validate_bytecode(module: BytecodeModule) -> BytecodeValidationResult:
    """Validate a module with no VM execution or Python code evaluation."""
    errors: list[BytecodeValidationError] = []
    _validate_function_table(module, errors)
    for function in module.functions:
        _validate_function(module, function, errors)
    return BytecodeValidationResult(tuple(errors))


def _validate_function_table(
    module: BytecodeModule,
    errors: list[BytecodeValidationError],
) -> None:
    for entry, function in zip(module.function_table.entries, module.functions, strict=True):
        if (
            entry.definition_id != function.definition_id
            or entry.name != function.name
            or entry.arity != function.arity
        ):
            errors.append(
                BytecodeValidationError(
                    BytecodeValidationCode.FUNCTION_TABLE_MISMATCH,
                    "function metadata does not match its table entry",
                    function.function_id,
                )
            )


def _validate_function(
    module: BytecodeModule,
    function: BytecodeFunction,
    errors: list[BytecodeValidationError],
) -> None:
    instructions = function.instructions
    if not instructions:
        errors.append(
            BytecodeValidationError(
                BytecodeValidationCode.EMPTY_FUNCTION,
                "function has no instructions",
                function.function_id,
            )
        )
        return
    for index, instruction in enumerate(instructions):
        _validate_instruction_operands(module, function, instruction, index, errors)
    _validate_stack_flow(function, errors)


def _validate_instruction_operands(
    module: BytecodeModule,
    function: BytecodeFunction,
    instruction: object,
    index: int,
    errors: list[BytecodeValidationError],
) -> None:
    location = InstructionIndex(index)
    if not isinstance(
        instruction,
        (
            PushConstant,
            PushFunction,
            LoadLocal,
            StoreLocal,
            Negate,
            Call,
            BuildRecord,
            LoadField,
            Jump,
            JumpIfFalse,
            Return,
            TraceExpression,
        ),
    ):
        errors.append(
            _error(
                BytecodeValidationCode.INVALID_INSTRUCTION,
                "unknown instruction",
                function,
                location,
            )
        )
        return
    if isinstance(instruction, PushConstant):
        if not isinstance(
            instruction.constant_id, ConstantId
        ) or instruction.constant_id.value >= len(module.constants.values):
            errors.append(
                _error(
                    BytecodeValidationCode.INVALID_CONSTANT,
                    "constant ID is outside the pool",
                    function,
                    location,
                )
            )
    elif isinstance(instruction, PushFunction):
        if not isinstance(
            instruction.function_id, FunctionId
        ) or instruction.function_id.value >= len(module.functions):
            errors.append(
                _error(
                    BytecodeValidationCode.INVALID_FUNCTION,
                    "function ID is outside the table",
                    function,
                    location,
                )
            )
    elif isinstance(instruction, (LoadLocal, StoreLocal)):
        if (
            not isinstance(instruction.slot, LocalSlot)
            or instruction.slot.value >= function.local_slot_count
        ):
            errors.append(
                _error(
                    BytecodeValidationCode.INVALID_LOCAL_SLOT,
                    "local slot is outside the frame",
                    function,
                    location,
                )
            )
    elif isinstance(instruction, (Jump, JumpIfFalse)):
        if not isinstance(instruction.target, InstructionIndex) or instruction.target.value >= len(
            function.instructions
        ):
            errors.append(
                _error(
                    BytecodeValidationCode.INVALID_JUMP,
                    "jump target is outside the function",
                    function,
                    location,
                )
            )


def _validate_stack_flow(
    function: BytecodeFunction,
    errors: list[BytecodeValidationError],
) -> None:
    pending: list[tuple[int, int]] = [(0, 0)]
    cursor = 0
    heights: list[int | None] = [None] * len(function.instructions)
    while cursor < len(pending):
        index, height = pending[cursor]
        cursor += 1
        prior_height = heights[index]
        if prior_height is not None:
            if prior_height != height:
                errors.append(
                    _error(
                        BytecodeValidationCode.INCONSISTENT_STACK_HEIGHT,
                        "control-flow paths reach different stack heights",
                        function,
                        InstructionIndex(index),
                    )
                )
            continue
        heights[index] = height
        instruction = function.instructions[index]
        if isinstance(instruction, Return) and height > 1:
            errors.append(
                _error(
                    BytecodeValidationCode.RETURN_STACK_HEIGHT,
                    "return must leave exactly one stack value",
                    function,
                    InstructionIndex(index),
                )
            )
        needed, resulting_height = _stack_effect(instruction, height)
        if height < needed:
            errors.append(
                _error(
                    BytecodeValidationCode.STACK_UNDERFLOW,
                    "instruction requires more stack values than are available",
                    function,
                    InstructionIndex(index),
                )
            )
            continue
        successors = _successors(instruction, index, len(function.instructions))
        for successor in successors:
            if successor is None:
                errors.append(
                    _error(
                        BytecodeValidationCode.CONTROL_FLOW_FALLTHROUGH,
                        "control flow reaches the end without return",
                        function,
                        InstructionIndex(index),
                    )
                )
            else:
                pending.append((successor, resulting_height))


_INSTRUCTION_TYPES = (
    PushConstant,
    PushFunction,
    LoadLocal,
    StoreLocal,
    Negate,
    Call,
    BuildRecord,
    LoadField,
    Jump,
    JumpIfFalse,
    Return,
    TraceExpression,
)


def _stack_effect(instruction: BytecodeInstruction, height: int) -> tuple[int, int]:
    if isinstance(instruction, (PushConstant, PushFunction, LoadLocal)):
        return (0, height + 1)
    if isinstance(instruction, StoreLocal):
        return (1, height - 1)
    if isinstance(instruction, Negate):
        return (1, height)
    if isinstance(instruction, Call):
        return (instruction.argument_count + 1, height - instruction.argument_count)
    if isinstance(instruction, BuildRecord):
        return (len(instruction.field_names), height - len(instruction.field_names) + 1)
    if isinstance(instruction, LoadField):
        return (1, height)
    if isinstance(instruction, JumpIfFalse):
        return (1, height - 1)
    if isinstance(instruction, Return):
        return (1, height - 1)
    return (0, height)


def _successors(
    instruction: BytecodeInstruction,
    index: int,
    instruction_count: int,
) -> tuple[int | None, ...]:
    next_index = index + 1 if index + 1 < instruction_count else None
    if isinstance(instruction, Return):
        return ()
    if isinstance(instruction, Jump):
        return (instruction.target.value,) if instruction.target.value < instruction_count else ()
    if isinstance(instruction, JumpIfFalse):
        target = (
            instruction.target.value if instruction.target.value < instruction_count else next_index
        )
        return (target, next_index)
    return (next_index,)


def _error(
    code: BytecodeValidationCode,
    message: str,
    function: BytecodeFunction,
    instruction_index: InstructionIndex,
) -> BytecodeValidationError:
    return BytecodeValidationError(code, message, function.function_id, instruction_index)
