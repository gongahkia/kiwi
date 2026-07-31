"""Deterministic bounded stack VM for validated Kiwi bytecode."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from enum import StrEnum

from kiwi.dsl.bytecode import (
    BuildRecord,
    BuildSome,
    BytecodeFunction,
    BytecodeModule,
    Call,
    InstructionIndex,
    InstructionSourceMapEntry,
    Jump,
    JumpIfFalse,
    JumpIfNone,
    LoadField,
    LoadLocal,
    Negate,
    Pop,
    PushConstant,
    PushFunction,
    PushNone,
    Return,
    StoreLocal,
    TraceExpression,
    UnwrapSome,
)
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.runtime_values import (
    BooleanValue,
    FunctionValue,
    IntegerValue,
    OptionNoneValue,
    OptionSomeValue,
    QuantityValue,
    RecordValue,
    RuntimeValue,
    StringValue,
    UnitValue,
)
from kiwi.dsl.validator import BytecodeValidationError, validate_bytecode


class VMFaultCode(StrEnum):
    """Stable faults returned by bounded VM execution."""

    INVALID_BYTECODE = "R001_INVALID_BYTECODE"
    INSTRUCTION_BUDGET = "R002_INSTRUCTION_BUDGET"
    ALLOCATION_BUDGET = "R003_ALLOCATION_BUDGET"
    STACK_BUDGET = "R004_STACK_BUDGET"
    INVALID_FIELD = "R005_INVALID_FIELD"
    CALL_DEPTH_BUDGET = "R009_CALL_DEPTH_BUDGET"
    TYPE = "R010_TYPE"
    CALL = "R011_CALL"
    UNINITIALIZED_LOCAL = "R012_UNINITIALIZED_LOCAL"
    ENTRY = "R013_ENTRY"


def _require_nonnegative(value: int, name: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ValueError(f"{name} must be a non-negative integer")


@dataclass(frozen=True, slots=True)
class VMBudgets:
    """Deterministic resource limits for one VM invocation."""

    instruction_limit: int = 10_000
    stack_limit: int = 1_024
    call_depth_limit: int = 64
    allocation_limit: int = 1_024

    def __post_init__(self) -> None:
        _require_nonnegative(self.instruction_limit, "instruction limit")
        _require_nonnegative(self.stack_limit, "stack limit")
        _require_nonnegative(self.allocation_limit, "allocation limit")
        if (
            not isinstance(self.call_depth_limit, int)
            or isinstance(self.call_depth_limit, bool)
            or self.call_depth_limit < 1
        ):
            raise ValueError("call depth limit must be a positive integer")


DEFAULT_VM_BUDGETS = VMBudgets()


@dataclass(frozen=True, slots=True)
class VMFault:
    """A structured execution failure without a Python stack trace."""

    code: VMFaultCode
    message: str
    function_id: FunctionId | None = None
    instruction_index: int | None = None
    source_map_entry: InstructionSourceMapEntry | None = None
    validation_errors: tuple[BytecodeValidationError, ...] = ()


@dataclass(frozen=True, slots=True)
class VMRunResult:
    """A VM value or fault; fallback runs retain their original fault."""

    value: RuntimeValue | None
    fault: VMFault | None = None

    @property
    def succeeded(self) -> bool:
        """Return whether the VM reached a normal top-level return."""
        return self.fault is None


@dataclass(slots=True)
class _Frame:
    function: BytecodeFunction
    locals_: list[RuntimeValue | None]
    stack_base: int
    instruction_index: int = 0


def run_vm(
    module: BytecodeModule,
    entry_function_id: FunctionId,
    arguments: Sequence[RuntimeValue],
    budgets: VMBudgets = DEFAULT_VM_BUDGETS,
) -> VMRunResult:
    """Validate and execute bytecode with deterministic resource limits."""
    validation = validate_bytecode(module)
    if not validation.is_valid:
        return VMRunResult(
            None,
            VMFault(
                VMFaultCode.INVALID_BYTECODE,
                "bytecode validation failed",
                validation_errors=validation.errors,
            ),
        )
    if not isinstance(entry_function_id, FunctionId) or entry_function_id.value >= len(
        module.functions
    ):
        return VMRunResult(None, VMFault(VMFaultCode.ENTRY, "entry function is outside the module"))
    if any(
        not isinstance(
            argument,
            (
                IntegerValue,
                BooleanValue,
                StringValue,
                QuantityValue,
                OptionSomeValue,
                OptionNoneValue,
                RecordValue,
                FunctionValue,
                UnitValue,
            ),
        )
        for argument in arguments
    ):
        return VMRunResult(
            None, VMFault(VMFaultCode.ENTRY, "entry arguments are not runtime values")
        )
    entry = module.functions[entry_function_id.value]
    if len(arguments) != entry.arity:
        return VMRunResult(
            None,
            VMFault(
                VMFaultCode.ENTRY,
                "entry argument count does not match function arity",
                entry.function_id,
            ),
        )
    frames = [_frame(entry, tuple(arguments), 0)]
    stack: list[RuntimeValue] = []
    executed = 0
    allocations = 0
    while frames:
        frame = frames[-1]
        if executed >= budgets.instruction_limit:
            return _fault(
                module,
                VMFaultCode.INSTRUCTION_BUDGET,
                "instruction budget exhausted",
                frame,
                instruction_index=frame.instruction_index,
            )
        instruction = frame.function.instructions[frame.instruction_index]
        executed += 1
        frame.instruction_index += 1
        if isinstance(instruction, PushConstant):
            if not _push(stack, module.constants.values[instruction.constant_id.value], budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, PushFunction):
            if allocations >= budgets.allocation_limit:
                return _fault(
                    module, VMFaultCode.ALLOCATION_BUDGET, "allocation budget exhausted", frame
                )
            allocations += 1
            if not _push(stack, FunctionValue(instruction.function_id), budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, LoadLocal):
            value = frame.locals_[instruction.slot.value]
            if value is None:
                return _fault(
                    module, VMFaultCode.UNINITIALIZED_LOCAL, "local slot is uninitialized", frame
                )
            if not _push(stack, value, budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, StoreLocal):
            value = _pop(stack, frame.stack_base)
            if value is None:
                return _fault(
                    module, VMFaultCode.INVALID_BYTECODE, "store has no stack value", frame
                )
            frame.locals_[instruction.slot.value] = value
        elif isinstance(instruction, Negate):
            value = _pop(stack, frame.stack_base)
            if not isinstance(value, IntegerValue):
                return _fault(module, VMFaultCode.TYPE, "negate requires an integer value", frame)
            if allocations >= budgets.allocation_limit:
                return _fault(
                    module, VMFaultCode.ALLOCATION_BUDGET, "allocation budget exhausted", frame
                )
            allocations += 1
            if not _push(stack, IntegerValue(-value.value), budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, BuildRecord):
            start = len(stack) - len(instruction.field_names)
            if start < frame.stack_base:
                return _fault(
                    module,
                    VMFaultCode.INVALID_BYTECODE,
                    "record construction has insufficient stack values",
                    frame,
                )
            values = tuple(stack[start:])
            del stack[start:]
            if allocations >= budgets.allocation_limit:
                return _fault(
                    module, VMFaultCode.ALLOCATION_BUDGET, "allocation budget exhausted", frame
                )
            allocations += 1
            fields = tuple(
                sorted(
                    zip(instruction.field_names, values, strict=True), key=lambda field: field[0]
                )
            )
            record = RecordValue(
                instruction.type_name,
                tuple(field[0] for field in fields),
                tuple(field[1] for field in fields),
            )
            if not _push(stack, record, budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, BuildSome):
            value = _pop(stack, frame.stack_base)
            if value is None:
                return _fault(
                    module,
                    VMFaultCode.INVALID_BYTECODE,
                    "Option construction has no stack value",
                    frame,
                )
            if allocations >= budgets.allocation_limit:
                return _fault(
                    module, VMFaultCode.ALLOCATION_BUDGET, "allocation budget exhausted", frame
                )
            allocations += 1
            if not _push(stack, OptionSomeValue(value), budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, PushNone):
            if allocations >= budgets.allocation_limit:
                return _fault(
                    module, VMFaultCode.ALLOCATION_BUDGET, "allocation budget exhausted", frame
                )
            allocations += 1
            if not _push(stack, OptionNoneValue(), budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, JumpIfNone):
            if len(stack) <= frame.stack_base:
                return _fault(
                    module,
                    VMFaultCode.INVALID_BYTECODE,
                    "Option match has no stack value",
                    frame,
                )
            match_value = stack[-1]
            if isinstance(match_value, OptionNoneValue):
                frame.instruction_index = instruction.target.value
            elif not isinstance(match_value, OptionSomeValue):
                return _fault(
                    module,
                    VMFaultCode.TYPE,
                    "Option match requires an Option value",
                    frame,
                )
        elif isinstance(instruction, UnwrapSome):
            some_value = _pop(stack, frame.stack_base)
            if not isinstance(some_value, OptionSomeValue):
                return _fault(
                    module,
                    VMFaultCode.TYPE,
                    "Some match arm requires a payload-bearing Option value",
                    frame,
                )
            if not _push(stack, some_value.value, budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, Pop):
            if _pop(stack, frame.stack_base) is None:
                return _fault(
                    module,
                    VMFaultCode.INVALID_BYTECODE,
                    "pop has no stack value",
                    frame,
                )
        elif isinstance(instruction, LoadField):
            record_value = _pop(stack, frame.stack_base)
            if not isinstance(record_value, RecordValue):
                return _fault(
                    module,
                    VMFaultCode.TYPE,
                    "field access requires a record value",
                    frame,
                )
            field_value = record_value.field_value(instruction.field_name)
            if field_value is None:
                return _fault(
                    module,
                    VMFaultCode.INVALID_FIELD,
                    f"record has no field '{instruction.field_name}'",
                    frame,
                )
            if not _push(stack, field_value, budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, Call):
            start = len(stack) - instruction.argument_count - 1
            if start < frame.stack_base:
                return _fault(
                    module,
                    VMFaultCode.INVALID_BYTECODE,
                    "call has insufficient stack values",
                    frame,
                )
            callee = stack[start]
            call_arguments = tuple(stack[start + 1 :])
            del stack[start:]
            if not isinstance(callee, FunctionValue):
                return _fault(module, VMFaultCode.CALL, "call requires a function value", frame)
            if callee.function_id.value >= len(module.functions):
                return _fault(
                    module, VMFaultCode.CALL, "function value is outside the module", frame
                )
            target = module.functions[callee.function_id.value]
            if len(call_arguments) != target.arity:
                return _fault(
                    module,
                    VMFaultCode.CALL,
                    "call argument count does not match function arity",
                    frame,
                )
            if len(frames) >= budgets.call_depth_limit:
                return _fault(
                    module, VMFaultCode.CALL_DEPTH_BUDGET, "call-depth budget exhausted", frame
                )
            frames.append(_frame(target, call_arguments, len(stack)))
        elif isinstance(instruction, Jump):
            frame.instruction_index = instruction.target.value
        elif isinstance(instruction, JumpIfFalse):
            value = _pop(stack, frame.stack_base)
            if not isinstance(value, BooleanValue):
                return _fault(
                    module, VMFaultCode.TYPE, "conditional jump requires a boolean value", frame
                )
            if not value.value:
                frame.instruction_index = instruction.target.value
        elif isinstance(instruction, Return):
            value = _pop(stack, frame.stack_base)
            if value is None or len(stack) != frame.stack_base:
                return _fault(
                    module, VMFaultCode.INVALID_BYTECODE, "return frame stack is invalid", frame
                )
            frames.pop()
            if not frames:
                return VMRunResult(value)
            if not _push(stack, value, budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, TraceExpression):
            continue
    raise AssertionError("VM exited without a return or fault")


def run_vm_with_fallback(
    module: BytecodeModule,
    entry_function_id: FunctionId,
    arguments: Sequence[RuntimeValue],
    fallback: RuntimeValue,
    budgets: VMBudgets = DEFAULT_VM_BUDGETS,
) -> VMRunResult:
    """Execute bytecode and return an explicit immutable fallback after a fault."""
    if not isinstance(
        fallback,
        (
            IntegerValue,
            BooleanValue,
            StringValue,
            QuantityValue,
            OptionSomeValue,
            OptionNoneValue,
            RecordValue,
            FunctionValue,
            UnitValue,
        ),
    ):
        raise ValueError("fallback must be a runtime value")
    result = run_vm(module, entry_function_id, arguments, budgets)
    return result if result.succeeded else VMRunResult(fallback, result.fault)


def _frame(
    function: BytecodeFunction,
    arguments: tuple[RuntimeValue, ...],
    stack_base: int,
) -> _Frame:
    locals_: list[RuntimeValue | None] = [None] * function.local_slot_count
    for index, argument in enumerate(arguments):
        locals_[index] = argument
    return _Frame(function, locals_, stack_base)


def _push(stack: list[RuntimeValue], value: RuntimeValue, budgets: VMBudgets) -> bool:
    if len(stack) >= budgets.stack_limit:
        return False
    stack.append(value)
    return True


def _pop(stack: list[RuntimeValue], stack_base: int) -> RuntimeValue | None:
    if len(stack) <= stack_base:
        return None
    return stack.pop()


def _fault(
    module: BytecodeModule,
    code: VMFaultCode,
    message: str,
    frame: _Frame,
    *,
    instruction_index: int | None = None,
) -> VMRunResult:
    """Build a source-linked fault for the active or attempted instruction."""
    index = frame.instruction_index - 1 if instruction_index is None else instruction_index
    source_map_entry = module.source_map.entry_for(
        frame.function.function_id,
        InstructionIndex(index),
    )
    return VMRunResult(
        None,
        VMFault(code, message, frame.function.function_id, index, source_map_entry),
    )
