"""Deterministic bounded stack VM for validated Kiwi bytecode."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from enum import StrEnum

from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.dsl.bytecode import (
    BinaryOperation,
    BuildClosure,
    BuildList,
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
    PushIntrinsic,
    PushNone,
    Return,
    StoreLocal,
    TraceExpression,
    UnwrapSome,
)
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.intrinsics import IntrinsicKind
from kiwi.dsl.operators import BinaryOperator
from kiwi.dsl.runtime_values import (
    BooleanValue,
    ClosureValue,
    FunctionValue,
    IntegerValue,
    IntrinsicValue,
    ListValue,
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


@dataclass(slots=True)
class _IntrinsicFrame:
    """One bounded native continuation awaiting deterministic callbacks."""

    intrinsic: IntrinsicKind
    values: tuple[RuntimeValue, ...]
    callback: FunctionValue | ClosureValue
    function_id: FunctionId
    instruction_index: int
    accumulator: RuntimeValue | None = None
    index: int = 0
    pending_value: RuntimeValue | None = None
    outputs: list[RuntimeValue] = field(default_factory=list)
    keys: list[RuntimeValue] = field(default_factory=list)
    selected_index: int | None = None
    best_key: RuntimeValue | None = None


@dataclass(slots=True)
class _ExecutionResources:
    """Shared mutable counters for every frame in one VM invocation."""

    instructions: int = 0
    allocations: int = 0


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
                ListValue,
                OptionSomeValue,
                OptionNoneValue,
                RecordValue,
                FunctionValue,
                ClosureValue,
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
    frames: list[_Frame | _IntrinsicFrame] = [_frame(entry, tuple(arguments), 0)]
    stack: list[RuntimeValue] = []
    resources = _ExecutionResources()
    while frames:
        active_frame = frames[-1]
        if isinstance(active_frame, _IntrinsicFrame):
            intrinsic_result = _advance_intrinsic(
                module,
                active_frame,
                frames,
                stack,
                budgets,
                resources,
            )
            if intrinsic_result is not None:
                return intrinsic_result
            continue
        frame = active_frame
        if resources.instructions >= budgets.instruction_limit:
            return _fault(
                module,
                VMFaultCode.INSTRUCTION_BUDGET,
                "instruction budget exhausted",
                frame,
                instruction_index=frame.instruction_index,
            )
        instruction = frame.function.instructions[frame.instruction_index]
        resources.instructions += 1
        frame.instruction_index += 1
        if isinstance(instruction, PushConstant):
            if not _push(stack, module.constants.values[instruction.constant_id.value], budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, PushIntrinsic):
            if resources.allocations >= budgets.allocation_limit:
                return _fault(
                    module, VMFaultCode.ALLOCATION_BUDGET, "allocation budget exhausted", frame
                )
            resources.allocations += 1
            if not _push(stack, IntrinsicValue(instruction.intrinsic), budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, PushFunction):
            if resources.allocations >= budgets.allocation_limit:
                return _fault(
                    module, VMFaultCode.ALLOCATION_BUDGET, "allocation budget exhausted", frame
                )
            resources.allocations += 1
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
            if resources.allocations >= budgets.allocation_limit:
                return _fault(
                    module, VMFaultCode.ALLOCATION_BUDGET, "allocation budget exhausted", frame
                )
            resources.allocations += 1
            if not _push(stack, IntegerValue(-value.value), budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, BinaryOperation):
            right = _pop(stack, frame.stack_base)
            left = _pop(stack, frame.stack_base)
            if left is None or right is None:
                return _fault(
                    module,
                    VMFaultCode.INVALID_BYTECODE,
                    "binary operation has insufficient stack values",
                    frame,
                )
            binary_result = _apply_binary_operation(instruction.operator, left, right)
            if binary_result is None:
                return _fault(
                    module,
                    VMFaultCode.TYPE,
                    "binary operation has incompatible runtime values",
                    frame,
                )
            value, allocation_cost = binary_result
            if resources.allocations + allocation_cost > budgets.allocation_limit:
                return _fault(
                    module, VMFaultCode.ALLOCATION_BUDGET, "allocation budget exhausted", frame
                )
            resources.allocations += allocation_cost
            if not _push(stack, value, budgets):
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
            if resources.allocations >= budgets.allocation_limit:
                return _fault(
                    module, VMFaultCode.ALLOCATION_BUDGET, "allocation budget exhausted", frame
                )
            resources.allocations += 1
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
        elif isinstance(instruction, BuildList):
            start = len(stack) - instruction.element_count
            if start < frame.stack_base:
                return _fault(
                    module,
                    VMFaultCode.INVALID_BYTECODE,
                    "list construction has insufficient stack values",
                    frame,
                )
            values = tuple(stack[start:])
            del stack[start:]
            allocation_cost = instruction.element_count + 1
            if resources.allocations + allocation_cost > budgets.allocation_limit:
                return _fault(
                    module, VMFaultCode.ALLOCATION_BUDGET, "allocation budget exhausted", frame
                )
            resources.allocations += allocation_cost
            if not _push(stack, ListValue(values), budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, BuildClosure):
            start = len(stack) - instruction.capture_count
            if start < frame.stack_base:
                return _fault(
                    module,
                    VMFaultCode.INVALID_BYTECODE,
                    "closure construction has insufficient stack values",
                    frame,
                )
            captures = tuple(stack[start:])
            del stack[start:]
            allocation_cost = instruction.capture_count + 1
            if resources.allocations + allocation_cost > budgets.allocation_limit:
                return _fault(
                    module, VMFaultCode.ALLOCATION_BUDGET, "allocation budget exhausted", frame
                )
            resources.allocations += allocation_cost
            if not _push(
                stack,
                ClosureValue(instruction.function_id, captures),
                budgets,
            ):
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
            if resources.allocations >= budgets.allocation_limit:
                return _fault(
                    module, VMFaultCode.ALLOCATION_BUDGET, "allocation budget exhausted", frame
                )
            resources.allocations += 1
            if not _push(stack, OptionSomeValue(value), budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, PushNone):
            if resources.allocations >= budgets.allocation_limit:
                return _fault(
                    module, VMFaultCode.ALLOCATION_BUDGET, "allocation budget exhausted", frame
                )
            resources.allocations += 1
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
            if isinstance(callee, IntrinsicValue):
                intrinsic_frame = _new_intrinsic_frame(
                    module,
                    callee.intrinsic,
                    call_arguments,
                    frame.function.function_id,
                    frame.instruction_index - 1,
                )
                if isinstance(intrinsic_frame, VMFault):
                    return VMRunResult(None, intrinsic_frame)
                if len(frames) >= budgets.call_depth_limit:
                    return _fault(
                        module,
                        VMFaultCode.CALL_DEPTH_BUDGET,
                        "call-depth budget exhausted",
                        frame,
                    )
                frames.append(intrinsic_frame)
                continue
            if isinstance(callee, FunctionValue):
                captured_arguments: tuple[RuntimeValue, ...] = ()
            elif isinstance(callee, ClosureValue):
                captured_arguments = callee.captures
            else:
                return _fault(module, VMFaultCode.CALL, "call requires a function value", frame)
            if callee.function_id.value >= len(module.functions):
                return _fault(
                    module, VMFaultCode.CALL, "function value is outside the module", frame
                )
            target = module.functions[callee.function_id.value]
            all_arguments = captured_arguments + call_arguments
            if len(all_arguments) != target.arity:
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
            frames.append(_frame(target, all_arguments, len(stack)))
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
            if isinstance(frames[-1], _IntrinsicFrame):
                frames[-1].pending_value = value
                continue
            if not _push(stack, value, budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, TraceExpression):
            continue
    raise AssertionError("VM exited without a return or fault")


def _apply_binary_operation(
    operator: BinaryOperator,
    left: RuntimeValue,
    right: RuntimeValue,
) -> tuple[RuntimeValue, int] | None:
    if operator in {
        BinaryOperator.LESS,
        BinaryOperator.LESS_EQUAL,
        BinaryOperator.GREATER,
        BinaryOperator.GREATER_EQUAL,
    }:
        comparison = _compare_domain_quantities(left, right)
        if comparison is None:
            return None
        if operator is BinaryOperator.LESS:
            result = comparison < 0
        elif operator is BinaryOperator.LESS_EQUAL:
            result = comparison <= 0
        elif operator is BinaryOperator.GREATER:
            result = comparison > 0
        elif operator is BinaryOperator.GREATER_EQUAL:
            result = comparison >= 0
        else:
            raise AssertionError("unknown comparison operator")
        return BooleanValue(result), 1
    if operator is BinaryOperator.ADD:
        quantity = _combine_domain_quantities(left, right, subtract=False)
        if quantity is not None:
            return quantity, 1
        position_vector = _combine_coordinate_records(
            left,
            right,
            "Position",
            ("x", "y"),
            "Vector",
            ("dx", "dy"),
            False,
        )
        if position_vector is not None:
            return position_vector
        return _combine_coordinate_records(
            left,
            right,
            "Vector",
            ("dx", "dy"),
            "Vector",
            ("dx", "dy"),
            False,
        )
    if operator is BinaryOperator.SUBTRACT:
        quantity = _combine_domain_quantities(left, right, subtract=True)
        if quantity is not None:
            return quantity, 1
        position_vector = _combine_coordinate_records(
            left,
            right,
            "Position",
            ("x", "y"),
            "Vector",
            ("dx", "dy"),
            True,
        )
        if position_vector is not None:
            return position_vector
        position_difference = _combine_coordinate_records(
            left,
            right,
            "Position",
            ("x", "y"),
            "Position",
            ("x", "y"),
            True,
            result_type_name="Vector",
            result_field_names=("dx", "dy"),
        )
        if position_difference is not None:
            return position_difference
        return _combine_coordinate_records(
            left,
            right,
            "Vector",
            ("dx", "dy"),
            "Vector",
            ("dx", "dy"),
            True,
        )
    raise AssertionError("unknown binary operator")


def _compare_domain_quantities(left: RuntimeValue, right: RuntimeValue) -> int | None:
    if not isinstance(left, QuantityValue) or not isinstance(right, QuantityValue):
        return None
    if left.value.dimension not in {
        QuantityDimension.DURATION,
        QuantityDimension.DISTANCE,
        QuantityDimension.PROBABILITY,
    }:
        return None
    return _compare_orderable(left, right)


def _combine_domain_quantities(
    left: RuntimeValue,
    right: RuntimeValue,
    *,
    subtract: bool,
) -> QuantityValue | None:
    if not isinstance(left, QuantityValue) or not isinstance(right, QuantityValue):
        return None
    if left.value.dimension != right.value.dimension or left.value.dimension not in {
        QuantityDimension.DURATION,
        QuantityDimension.DISTANCE,
    }:
        return None
    return _combine_quantities(left, right, subtract)


def _combine_coordinate_records(
    left: RuntimeValue,
    right: RuntimeValue,
    left_type_name: str,
    left_field_names: tuple[str, str],
    right_type_name: str,
    right_field_names: tuple[str, str],
    subtract: bool,
    *,
    result_type_name: str | None = None,
    result_field_names: tuple[str, str] | None = None,
) -> tuple[RecordValue, int] | None:
    left_values = _coordinate_components(left, left_type_name, left_field_names)
    right_values = _coordinate_components(right, right_type_name, right_field_names)
    if left_values is None or right_values is None:
        return None
    first = _combine_quantities(left_values[0], right_values[0], subtract)
    second = _combine_quantities(left_values[1], right_values[1], subtract)
    if first is None or second is None:
        return None
    target_type_name = result_type_name if result_type_name is not None else left_type_name
    target_field_names = result_field_names if result_field_names is not None else left_field_names
    return RecordValue(target_type_name, target_field_names, (first, second)), 3


def _coordinate_components(
    value: RuntimeValue,
    type_name: str,
    field_names: tuple[str, str],
) -> tuple[QuantityValue, QuantityValue] | None:
    if not isinstance(value, RecordValue) or value.type_name != type_name:
        return None
    if value.field_names != field_names:
        return None
    first = value.field_value(field_names[0])
    second = value.field_value(field_names[1])
    if not isinstance(first, QuantityValue) or not isinstance(second, QuantityValue):
        return None
    if (
        first.value.dimension is not QuantityDimension.DISTANCE
        or second.value.dimension is not QuantityDimension.DISTANCE
    ):
        return None
    return first, second


def _combine_quantities(
    left: QuantityValue,
    right: QuantityValue,
    subtract: bool,
) -> QuantityValue | None:
    if left.value.dimension != right.value.dimension:
        return None
    left_value = left.value.value
    right_value = right.value.value
    numerator = left_value.numerator * right_value.denominator
    adjustment = right_value.numerator * left_value.denominator
    if subtract:
        numerator -= adjustment
    else:
        numerator += adjustment
    denominator = left_value.denominator * right_value.denominator
    return QuantityValue(Quantity(left.value.dimension, ExactRational(numerator, denominator)))


def _new_intrinsic_frame(
    module: BytecodeModule,
    intrinsic: IntrinsicKind,
    arguments: tuple[RuntimeValue, ...],
    function_id: FunctionId,
    instruction_index: int,
) -> _IntrinsicFrame | VMFault:
    expected_arity = 3 if intrinsic is IntrinsicKind.LIST_FOLD else 2
    if len(arguments) != expected_arity:
        return _intrinsic_fault(
            module,
            VMFaultCode.CALL,
            "intrinsic call argument count does not match function arity",
            function_id,
            instruction_index,
        )
    if not isinstance(arguments[0], ListValue):
        return _intrinsic_fault(
            module,
            VMFaultCode.TYPE,
            "List intrinsic requires a List value",
            function_id,
            instruction_index,
        )
    callback_index = 2 if intrinsic is IntrinsicKind.LIST_FOLD else 1
    callback = arguments[callback_index]
    if not isinstance(callback, (FunctionValue, ClosureValue)):
        return _intrinsic_fault(
            module,
            VMFaultCode.TYPE,
            "List intrinsic requires a function callback",
            function_id,
            instruction_index,
        )
    accumulator = arguments[1] if intrinsic is IntrinsicKind.LIST_FOLD else None
    return _IntrinsicFrame(
        intrinsic,
        arguments[0].values,
        callback,
        function_id,
        instruction_index,
        accumulator,
    )


def _advance_intrinsic(
    module: BytecodeModule,
    frame: _IntrinsicFrame,
    frames: list[_Frame | _IntrinsicFrame],
    stack: list[RuntimeValue],
    budgets: VMBudgets,
    resources: _ExecutionResources,
) -> VMRunResult | None:
    if frame.intrinsic is IntrinsicKind.LIST_MAP:
        if frame.pending_value is not None:
            frame.outputs.append(frame.pending_value)
            frame.pending_value = None
        if frame.index == len(frame.values):
            return _complete_intrinsic(
                module,
                frame,
                frames,
                stack,
                budgets,
                resources,
                ListValue(tuple(frame.outputs)),
                len(frame.outputs) + 1,
            )
        value = frame.values[frame.index]
        frame.index += 1
        return _schedule_intrinsic_callback(
            module, frame, frames, stack, budgets, resources, (value,)
        )
    if frame.intrinsic is IntrinsicKind.LIST_FILTER:
        if frame.pending_value is not None:
            predicate = frame.pending_value
            frame.pending_value = None
            if not isinstance(predicate, BooleanValue):
                return _intrinsic_result(
                    module,
                    VMFaultCode.TYPE,
                    "List.filter callback must return Bool",
                    frame,
                )
            if predicate.value:
                frame.outputs.append(frame.values[frame.index - 1])
        if frame.index == len(frame.values):
            return _complete_intrinsic(
                module,
                frame,
                frames,
                stack,
                budgets,
                resources,
                ListValue(tuple(frame.outputs)),
                len(frame.outputs) + 1,
            )
        value = frame.values[frame.index]
        frame.index += 1
        return _schedule_intrinsic_callback(
            module, frame, frames, stack, budgets, resources, (value,)
        )
    if frame.intrinsic is IntrinsicKind.LIST_FIND:
        if frame.pending_value is not None:
            predicate = frame.pending_value
            frame.pending_value = None
            if not isinstance(predicate, BooleanValue):
                return _intrinsic_result(
                    module,
                    VMFaultCode.TYPE,
                    "List.find callback must return Bool",
                    frame,
                )
            if predicate.value:
                return _complete_intrinsic(
                    module,
                    frame,
                    frames,
                    stack,
                    budgets,
                    resources,
                    OptionSomeValue(frame.values[frame.index - 1]),
                    1,
                )
        if frame.index == len(frame.values):
            return _complete_intrinsic(
                module, frame, frames, stack, budgets, resources, OptionNoneValue(), 1
            )
        value = frame.values[frame.index]
        frame.index += 1
        return _schedule_intrinsic_callback(
            module, frame, frames, stack, budgets, resources, (value,)
        )
    if frame.intrinsic is IntrinsicKind.LIST_FOLD:
        if frame.pending_value is not None:
            frame.accumulator = frame.pending_value
            frame.pending_value = None
        if frame.index == len(frame.values):
            if frame.accumulator is None:
                raise AssertionError("fold intrinsic has no accumulator")
            return _complete_intrinsic(
                module, frame, frames, stack, budgets, resources, frame.accumulator, 0
            )
        if frame.accumulator is None:
            raise AssertionError("fold intrinsic has no accumulator")
        value = frame.values[frame.index]
        frame.index += 1
        return _schedule_intrinsic_callback(
            module, frame, frames, stack, budgets, resources, (frame.accumulator, value)
        )
    if frame.intrinsic is IntrinsicKind.LIST_MIN_BY:
        if frame.pending_value is not None:
            key = frame.pending_value
            frame.pending_value = None
            if frame.best_key is None:
                frame.best_key = key
                frame.selected_index = frame.index - 1
            else:
                work_fault = _consume_intrinsic_work(module, frame, budgets, resources)
                if work_fault is not None:
                    return work_fault
                comparison = _compare_orderable(key, frame.best_key)
                if comparison is None:
                    return _intrinsic_result(
                        module,
                        VMFaultCode.TYPE,
                        "List.min_by callback must return a same-kind orderable value",
                        frame,
                    )
                if comparison < 0:
                    frame.best_key = key
                    frame.selected_index = frame.index - 1
        if frame.index == len(frame.values):
            result: RuntimeValue
            if frame.selected_index is None:
                result = OptionNoneValue()
            else:
                result = OptionSomeValue(frame.values[frame.selected_index])
            return _complete_intrinsic(module, frame, frames, stack, budgets, resources, result, 1)
        value = frame.values[frame.index]
        frame.index += 1
        return _schedule_intrinsic_callback(
            module, frame, frames, stack, budgets, resources, (value,)
        )
    if frame.intrinsic is IntrinsicKind.LIST_SORT_BY:
        if frame.pending_value is not None:
            frame.keys.append(frame.pending_value)
            frame.pending_value = None
        if frame.index == len(frame.values):
            sorted_values = _stable_sorted_values(module, frame, budgets, resources)
            if isinstance(sorted_values, VMRunResult):
                return sorted_values
            return _complete_intrinsic(
                module,
                frame,
                frames,
                stack,
                budgets,
                resources,
                ListValue(sorted_values),
                len(sorted_values) + 1,
            )
        value = frame.values[frame.index]
        frame.index += 1
        return _schedule_intrinsic_callback(
            module, frame, frames, stack, budgets, resources, (value,)
        )
    raise AssertionError("unknown intrinsic kind")


def _schedule_intrinsic_callback(
    module: BytecodeModule,
    frame: _IntrinsicFrame,
    frames: list[_Frame | _IntrinsicFrame],
    stack: list[RuntimeValue],
    budgets: VMBudgets,
    resources: _ExecutionResources,
    arguments: tuple[RuntimeValue, ...],
) -> VMRunResult | None:
    work_fault = _consume_intrinsic_work(module, frame, budgets, resources)
    if work_fault is not None:
        return work_fault
    if isinstance(frame.callback, ClosureValue):
        captured_arguments = frame.callback.captures
    else:
        captured_arguments = ()
    if frame.callback.function_id.value >= len(module.functions):
        return _intrinsic_result(
            module,
            VMFaultCode.CALL,
            "intrinsic callback is outside the module",
            frame,
        )
    target = module.functions[frame.callback.function_id.value]
    all_arguments = captured_arguments + arguments
    if len(all_arguments) != target.arity:
        return _intrinsic_result(
            module,
            VMFaultCode.CALL,
            "intrinsic callback argument count does not match function arity",
            frame,
        )
    if len(frames) >= budgets.call_depth_limit:
        return _intrinsic_result(
            module,
            VMFaultCode.CALL_DEPTH_BUDGET,
            "call-depth budget exhausted",
            frame,
        )
    frames.append(_frame(target, all_arguments, len(stack)))
    return None


def _stable_sorted_values(
    module: BytecodeModule,
    frame: _IntrinsicFrame,
    budgets: VMBudgets,
    resources: _ExecutionResources,
) -> tuple[RuntimeValue, ...] | VMRunResult:
    if len(frame.keys) != len(frame.values):
        raise AssertionError("sort intrinsic has incomplete key evaluations")
    ordered_indices = list(range(len(frame.values)))
    for candidate_position in range(1, len(ordered_indices)):
        candidate_index = ordered_indices[candidate_position]
        insertion_position = candidate_position
        while insertion_position > 0:
            work_fault = _consume_intrinsic_work(module, frame, budgets, resources)
            if work_fault is not None:
                return work_fault
            prior_index = ordered_indices[insertion_position - 1]
            comparison = _compare_orderable(frame.keys[candidate_index], frame.keys[prior_index])
            if comparison is None:
                return _intrinsic_result(
                    module,
                    VMFaultCode.TYPE,
                    "List.sort_by callback must return same-kind orderable values",
                    frame,
                )
            if comparison >= 0:
                break
            ordered_indices[insertion_position] = prior_index
            insertion_position -= 1
        ordered_indices[insertion_position] = candidate_index
    return tuple(frame.values[index] for index in ordered_indices)


def _compare_orderable(left: RuntimeValue, right: RuntimeValue) -> int | None:
    if isinstance(left, IntegerValue) and isinstance(right, IntegerValue):
        return (left.value > right.value) - (left.value < right.value)
    if isinstance(left, BooleanValue) and isinstance(right, BooleanValue):
        return (left.value > right.value) - (left.value < right.value)
    if isinstance(left, StringValue) and isinstance(right, StringValue):
        return (left.value > right.value) - (left.value < right.value)
    if isinstance(left, QuantityValue) and isinstance(right, QuantityValue):
        if left.value.dimension != right.value.dimension:
            return None
        left_value = left.value.value
        right_value = right.value.value
        difference = (
            left_value.numerator * right_value.denominator
            - right_value.numerator * left_value.denominator
        )
        return (difference > 0) - (difference < 0)
    return None


def _consume_intrinsic_work(
    module: BytecodeModule,
    frame: _IntrinsicFrame,
    budgets: VMBudgets,
    resources: _ExecutionResources,
) -> VMRunResult | None:
    if resources.instructions >= budgets.instruction_limit:
        return _intrinsic_result(
            module,
            VMFaultCode.INSTRUCTION_BUDGET,
            "instruction budget exhausted",
            frame,
        )
    resources.instructions += 1
    return None


def _complete_intrinsic(
    module: BytecodeModule,
    frame: _IntrinsicFrame,
    frames: list[_Frame | _IntrinsicFrame],
    stack: list[RuntimeValue],
    budgets: VMBudgets,
    resources: _ExecutionResources,
    value: RuntimeValue,
    allocation_cost: int,
) -> VMRunResult | None:
    if resources.allocations + allocation_cost > budgets.allocation_limit:
        return _intrinsic_result(
            module,
            VMFaultCode.ALLOCATION_BUDGET,
            "allocation budget exhausted",
            frame,
        )
    resources.allocations += allocation_cost
    frames.pop()
    if not frames:
        return VMRunResult(value)
    if not _push(stack, value, budgets):
        return _intrinsic_result(
            module,
            VMFaultCode.STACK_BUDGET,
            "stack budget exhausted",
            frame,
        )
    return None


def _intrinsic_result(
    module: BytecodeModule,
    code: VMFaultCode,
    message: str,
    frame: _IntrinsicFrame,
) -> VMRunResult:
    return VMRunResult(
        None,
        _intrinsic_fault(
            module,
            code,
            message,
            frame.function_id,
            frame.instruction_index,
        ),
    )


def _intrinsic_fault(
    module: BytecodeModule,
    code: VMFaultCode,
    message: str,
    function_id: FunctionId,
    instruction_index: int,
) -> VMFault:
    return VMFault(
        code,
        message,
        function_id,
        instruction_index,
        module.source_map.entry_for(function_id, InstructionIndex(instruction_index)),
    )


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
            ListValue,
            OptionSomeValue,
            OptionNoneValue,
            RecordValue,
            FunctionValue,
            ClosureValue,
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
