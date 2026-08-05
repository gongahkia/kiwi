"""Deterministic bounded stack VM for validated Kiwi bytecode."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from enum import StrEnum

from kiwi.domain.ids import EventId
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
    strip_observation_metadata,
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


class CoverCandidateTraceStatus(StrEnum):
    """One final outcome for a scored Cover.nearest_safe candidate."""

    SELECTED = "selected"
    REJECTED = "rejected"


class CoverCandidateRejectionReason(StrEnum):
    """The first deterministic rank component that lost to the selected slot."""

    HIGHER_EXPOSURE = "higher_exposure"
    HIGHER_ROUTE_COST = "higher_route_cost"
    HIGHER_COVER_ID = "higher_cover_id"
    HIGHER_SLOT_INDEX = "higher_slot_index"


@dataclass(frozen=True, slots=True)
class CoverCandidateTrace:
    """One score and final outcome retained for a Cover.nearest_safe call."""

    cover_id: int
    slot_index: int
    side: str
    exposure_basis_points: int
    route_cost: Quantity
    status: CoverCandidateTraceStatus
    rejection_reason: CoverCandidateRejectionReason | None = None

    def __post_init__(self) -> None:
        if (
            not isinstance(self.cover_id, int)
            or isinstance(self.cover_id, bool)
            or self.cover_id <= 0
        ):
            raise ValueError("cover candidate trace requires a positive cover ID")
        if (
            not isinstance(self.slot_index, int)
            or isinstance(self.slot_index, bool)
            or self.slot_index < 0
        ):
            raise ValueError("cover candidate trace requires a non-negative slot index")
        if self.side not in ("left", "right"):
            raise ValueError("cover candidate trace requires a cover side")
        if (
            not isinstance(self.exposure_basis_points, int)
            or isinstance(self.exposure_basis_points, bool)
            or not 0 <= self.exposure_basis_points <= 10_000
        ):
            raise ValueError("cover candidate trace exposure must be between zero and 10,000")
        if (
            not isinstance(self.route_cost, Quantity)
            or self.route_cost.dimension is not QuantityDimension.DISTANCE
            or self.route_cost.value.numerator < 0
        ):
            raise ValueError("cover candidate trace route cost must be non-negative Distance")
        if not isinstance(self.status, CoverCandidateTraceStatus):
            raise ValueError("cover candidate trace requires a status")
        if self.status is CoverCandidateTraceStatus.SELECTED:
            if self.rejection_reason is not None:
                raise ValueError("selected cover candidate trace cannot have a rejection reason")
        elif not isinstance(self.rejection_reason, CoverCandidateRejectionReason):
            raise ValueError("rejected cover candidate trace requires a rejection reason")


@dataclass(frozen=True, slots=True)
class CoverSelectionTrace:
    """Source-linked semantic results for one Cover.nearest_safe invocation."""

    source_map_entry: InstructionSourceMapEntry
    candidates: tuple[CoverCandidateTrace, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.source_map_entry, InstructionSourceMapEntry):
            raise ValueError("cover selection trace requires an instruction source-map entry")
        if not isinstance(self.candidates, tuple):
            raise ValueError("cover selection trace candidates must be an immutable tuple")
        if any(not isinstance(candidate, CoverCandidateTrace) for candidate in self.candidates):
            raise ValueError("cover selection trace candidates must be cover candidate traces")
        if self.candidates and (
            self.candidates[0].status is not CoverCandidateTraceStatus.SELECTED
            or any(
                candidate.status is not CoverCandidateTraceStatus.REJECTED
                for candidate in self.candidates[1:]
            )
        ):
            raise ValueError("cover selection trace must retain one leading selected candidate")


@dataclass(frozen=True, slots=True)
class VMExpressionTrace:
    """One source-mapped expression entry executed during a VM invocation."""

    source_map_entry: InstructionSourceMapEntry

    def __post_init__(self) -> None:
        if not isinstance(self.source_map_entry, InstructionSourceMapEntry):
            raise ValueError("VM expression trace requires a source-map entry")


@dataclass(frozen=True, slots=True)
class VMObservationReadTrace:
    """One source-mapped field read from an observation-provenanced record."""

    source_map_entry: InstructionSourceMapEntry
    path: tuple[str, ...]
    value: RuntimeValue
    evidence_event_ids: tuple[EventId, ...]
    confidence_basis_points: int | None
    age_ticks: int | None

    def __post_init__(self) -> None:
        if not isinstance(self.source_map_entry, InstructionSourceMapEntry):
            raise ValueError("VM observation read trace requires a source-map entry")
        if not isinstance(self.path, tuple) or not self.path:
            raise ValueError("VM observation read trace requires a non-empty path")
        if any(not isinstance(part, str) or not part for part in self.path):
            raise ValueError("VM observation read trace path parts must be non-empty strings")
        if not isinstance(
            self.value,
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
                IntrinsicValue,
                UnitValue,
            ),
        ):
            raise ValueError("VM observation read trace value must be a runtime value")
        if not isinstance(self.evidence_event_ids, tuple):
            raise ValueError("VM observation read trace evidence IDs must be an immutable tuple")
        previous_id = 0
        for event_id in self.evidence_event_ids:
            if not isinstance(event_id, EventId):
                raise ValueError("VM observation read trace evidence IDs must contain event IDs")
            if event_id.value <= previous_id:
                raise ValueError(
                    "VM observation read trace evidence IDs must be unique and ascending"
                )
            previous_id = event_id.value
        if self.confidence_basis_points is not None and (
            not isinstance(self.confidence_basis_points, int)
            or isinstance(self.confidence_basis_points, bool)
            or not 0 <= self.confidence_basis_points <= 10_000
        ):
            raise ValueError("VM observation read trace confidence must be between zero and 10,000")
        if self.age_ticks is not None and (
            not isinstance(self.age_ticks, int)
            or isinstance(self.age_ticks, bool)
            or self.age_ticks < 0
        ):
            raise ValueError("VM observation read trace age must be a non-negative integer")


@dataclass(frozen=True, slots=True)
class VMRunResult:
    """A VM value or fault; fallback runs retain their original fault."""

    value: RuntimeValue | None
    fault: VMFault | None = None
    cover_selection_traces: tuple[CoverSelectionTrace, ...] = ()
    expression_traces: tuple[VMExpressionTrace, ...] = ()
    observation_read_traces: tuple[VMObservationReadTrace, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.cover_selection_traces, tuple):
            raise ValueError("VM cover selection traces must be an immutable tuple")
        if any(not isinstance(trace, CoverSelectionTrace) for trace in self.cover_selection_traces):
            raise ValueError("VM cover selection traces must be cover selection traces")
        if not isinstance(self.expression_traces, tuple):
            raise ValueError("VM expression traces must be an immutable tuple")
        if any(not isinstance(trace, VMExpressionTrace) for trace in self.expression_traces):
            raise ValueError("VM expression traces must be VM expression traces")
        if not isinstance(self.observation_read_traces, tuple):
            raise ValueError("VM observation read traces must be an immutable tuple")
        if any(
            not isinstance(trace, VMObservationReadTrace) for trace in self.observation_read_traces
        ):
            raise ValueError("VM observation read traces must be VM observation read traces")

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


@dataclass(frozen=True, slots=True)
class _CoverIntrinsicResult:
    """One completed Cover intrinsic value and its output allocation cost."""

    value: RuntimeValue
    allocation_cost: int
    candidate_scores: tuple[_CoverCandidateScore, ...] | None = None


@dataclass(frozen=True, slots=True)
class _CoverIntrinsicFailure:
    """One source-linked Cover intrinsic fault awaiting active-frame attachment."""

    code: VMFaultCode
    message: str


@dataclass(frozen=True, slots=True)
class _CoverPosition:
    """One exact planar position decoded from a closed runtime record."""

    x: ExactRational
    y: ExactRational


@dataclass(frozen=True, slots=True)
class _CoverSlotValue:
    """One validated observable cover slot."""

    position: _CoverPosition
    side: str
    slot_index: int


@dataclass(frozen=True, slots=True)
class _CoverValue:
    """One validated observable cover segment."""

    cover_id: int
    start: _CoverPosition
    end: _CoverPosition
    height: str
    integrity_basis_points: int
    slots: ListValue


@dataclass(frozen=True, slots=True)
class _CoverCandidateScore:
    """One parsed Cover.nearest_safe candidate before final trace projection."""

    cover_id: int
    slot: _CoverSlotValue
    exposure_basis_points: int
    route_cost: ExactRational


_COVER_INTRINSICS = frozenset(
    {
        IntrinsicKind.COVER_EXPOSURE,
        IntrinsicKind.COVER_ROUTE_COST,
        IntrinsicKind.COVER_NEAREST_SAFE,
        IntrinsicKind.COVER_SEEK,
    }
)


def run_vm(
    module: BytecodeModule,
    entry_function_id: FunctionId,
    arguments: Sequence[RuntimeValue],
    budgets: VMBudgets = DEFAULT_VM_BUDGETS,
    *,
    capture_cover_selection_trace: bool = False,
    capture_expression_trace: bool = False,
    capture_observation_read_trace: bool = False,
) -> VMRunResult:
    """Validate and execute bytecode with deterministic resource limits."""
    if not isinstance(capture_cover_selection_trace, bool):
        raise ValueError("cover selection trace capture must be a boolean")
    if not isinstance(capture_expression_trace, bool):
        raise ValueError("expression trace capture must be a boolean")
    if not isinstance(capture_observation_read_trace, bool):
        raise ValueError("observation read trace capture must be a boolean")
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
    cover_selection_traces: list[CoverSelectionTrace] = []
    expression_traces: list[VMExpressionTrace] = []
    observation_read_traces: list[VMObservationReadTrace] = []
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
            metadata = record_value.observation_field_metadata(instruction.field_name)
            if capture_observation_read_trace and metadata is not None:
                observation_read_traces.append(
                    VMObservationReadTrace(
                        module.source_map.entry_for(
                            frame.function.function_id,
                            InstructionIndex(frame.instruction_index - 1),
                        ),
                        metadata.path,
                        field_value,
                        metadata.evidence_event_ids,
                        metadata.confidence_basis_points,
                        metadata.age_ticks,
                    )
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
                if callee.intrinsic in _COVER_INTRINSICS:
                    cover_result = _run_cover_intrinsic(
                        callee.intrinsic,
                        call_arguments,
                        budgets,
                        resources,
                        capture_cover_selection_trace,
                    )
                    if isinstance(cover_result, _CoverIntrinsicFailure):
                        return _fault(module, cover_result.code, cover_result.message, frame)
                    if capture_cover_selection_trace and cover_result.candidate_scores is not None:
                        source_map_entry = module.source_map.entry_for(
                            frame.function.function_id,
                            InstructionIndex(frame.instruction_index - 1),
                        )
                        cover_selection_traces.append(
                            _cover_selection_trace(source_map_entry, cover_result.candidate_scores)
                        )
                    if (
                        resources.allocations + cover_result.allocation_cost
                        > budgets.allocation_limit
                    ):
                        return _fault(
                            module,
                            VMFaultCode.ALLOCATION_BUDGET,
                            "allocation budget exhausted",
                            frame,
                        )
                    resources.allocations += cover_result.allocation_cost
                    if not _push(stack, cover_result.value, budgets):
                        return _fault(
                            module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame
                        )
                    continue
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
                return VMRunResult(
                    strip_observation_metadata(value),
                    cover_selection_traces=tuple(cover_selection_traces),
                    expression_traces=tuple(expression_traces),
                    observation_read_traces=tuple(observation_read_traces),
                )
            if isinstance(frames[-1], _IntrinsicFrame):
                frames[-1].pending_value = value
                continue
            if not _push(stack, value, budgets):
                return _fault(module, VMFaultCode.STACK_BUDGET, "stack budget exhausted", frame)
        elif isinstance(instruction, TraceExpression):
            if capture_expression_trace:
                expression_traces.append(
                    VMExpressionTrace(
                        module.source_map.entry_for(
                            frame.function.function_id,
                            InstructionIndex(frame.instruction_index - 1),
                        )
                    )
                )
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


def _run_cover_intrinsic(
    intrinsic: IntrinsicKind,
    arguments: tuple[RuntimeValue, ...],
    budgets: VMBudgets,
    resources: _ExecutionResources,
    capture_cover_selection_trace: bool,
) -> _CoverIntrinsicResult | _CoverIntrinsicFailure:
    if not _consume_cover_work(budgets, resources):
        return _CoverIntrinsicFailure(
            VMFaultCode.INSTRUCTION_BUDGET,
            "instruction budget exhausted",
        )
    if intrinsic is IntrinsicKind.COVER_EXPOSURE:
        return _cover_exposure(arguments, budgets, resources)
    if intrinsic is IntrinsicKind.COVER_ROUTE_COST:
        return _cover_route_cost(arguments)
    if intrinsic is IntrinsicKind.COVER_NEAREST_SAFE:
        return _cover_nearest_safe(
            arguments,
            budgets,
            resources,
            capture_cover_selection_trace,
        )
    if intrinsic is IntrinsicKind.COVER_SEEK:
        return _cover_seek(arguments)
    raise AssertionError("unknown Cover intrinsic")


def _cover_exposure(
    arguments: tuple[RuntimeValue, ...],
    budgets: VMBudgets,
    resources: _ExecutionResources,
) -> _CoverIntrinsicResult | _CoverIntrinsicFailure:
    if len(arguments) != 3:
        return _cover_arity_failure(IntrinsicKind.COVER_EXPOSURE, 3)
    cover = _cover_value(arguments[0])
    slot = _cover_slot_value(arguments[1])
    threat_position = _contact_position(arguments[2])
    if cover is None or slot is None or threat_position is None:
        return _cover_type_failure(IntrinsicKind.COVER_EXPOSURE)
    found_slot = False
    for value in cover.slots.values:
        if not _consume_cover_work(budgets, resources):
            return _CoverIntrinsicFailure(
                VMFaultCode.INSTRUCTION_BUDGET,
                "instruction budget exhausted",
            )
        candidate = _cover_slot_value(value)
        if candidate is None:
            return _cover_type_failure(IntrinsicKind.COVER_EXPOSURE)
        if candidate == slot:
            found_slot = True
    if not found_slot:
        return _cover_type_failure(IntrinsicKind.COVER_EXPOSURE)
    return _CoverIntrinsicResult(
        IntegerValue(_cover_exposure_basis_points(cover, slot, threat_position)), 1
    )


def _cover_route_cost(
    arguments: tuple[RuntimeValue, ...],
) -> _CoverIntrinsicResult | _CoverIntrinsicFailure:
    if len(arguments) != 2:
        return _cover_arity_failure(IntrinsicKind.COVER_ROUTE_COST, 2)
    origin = _cover_position(arguments[0])
    slot = _cover_slot_value(arguments[1])
    if origin is None or slot is None:
        return _cover_type_failure(IntrinsicKind.COVER_ROUTE_COST)
    return _CoverIntrinsicResult(
        QuantityValue(
            Quantity(QuantityDimension.DISTANCE, _manhattan_distance(origin, slot.position))
        ),
        1,
    )


def _cover_nearest_safe(
    arguments: tuple[RuntimeValue, ...],
    budgets: VMBudgets,
    resources: _ExecutionResources,
    capture_cover_selection_trace: bool,
) -> _CoverIntrinsicResult | _CoverIntrinsicFailure:
    if len(arguments) != 3:
        return _cover_arity_failure(IntrinsicKind.COVER_NEAREST_SAFE, 3)
    covers, origin, threat_position = arguments
    if not isinstance(covers, ListValue):
        return _cover_type_failure(IntrinsicKind.COVER_NEAREST_SAFE)
    origin_position = _cover_position(origin)
    contact_position = _contact_position(threat_position)
    if origin_position is None or contact_position is None:
        return _cover_type_failure(IntrinsicKind.COVER_NEAREST_SAFE)
    trace_candidates: list[_CoverCandidateScore] | None = (
        [] if capture_cover_selection_trace else None
    )
    selected: _CoverCandidateScore | None = None
    previous_cover_id = 0
    for value in covers.values:
        if not _consume_cover_work(budgets, resources):
            return _CoverIntrinsicFailure(
                VMFaultCode.INSTRUCTION_BUDGET,
                "instruction budget exhausted",
            )
        cover = _cover_value(value)
        if cover is None or cover.cover_id <= previous_cover_id:
            return _cover_type_failure(IntrinsicKind.COVER_NEAREST_SAFE)
        previous_cover_id = cover.cover_id
        previous_slot_index = -1
        for slot_value in cover.slots.values:
            if not _consume_cover_work(budgets, resources):
                return _CoverIntrinsicFailure(
                    VMFaultCode.INSTRUCTION_BUDGET,
                    "instruction budget exhausted",
                )
            slot = _cover_slot_value(slot_value)
            if slot is None or slot.slot_index <= previous_slot_index:
                return _cover_type_failure(IntrinsicKind.COVER_NEAREST_SAFE)
            previous_slot_index = slot.slot_index
            exposure = _cover_exposure_basis_points(cover, slot, contact_position)
            route_cost = _manhattan_distance(origin_position, slot.position)
            candidate = _CoverCandidateScore(cover.cover_id, slot, exposure, route_cost)
            if trace_candidates is not None:
                trace_candidates.append(candidate)
            if selected is None or _is_safer_cover_candidate(candidate, selected):
                selected = candidate
    if selected is None:
        return _CoverIntrinsicResult(
            OptionNoneValue(),
            1,
            () if trace_candidates is not None else None,
        )
    intention = RecordValue(
        "TakeCover",
        ("cover_id", "side"),
        (IntegerValue(selected.cover_id), StringValue(selected.slot.side)),
    )
    return _CoverIntrinsicResult(
        OptionSomeValue(intention),
        2,
        tuple(trace_candidates) if trace_candidates is not None else None,
    )


def _cover_seek(
    arguments: tuple[RuntimeValue, ...],
) -> _CoverIntrinsicResult | _CoverIntrinsicFailure:
    if len(arguments) != 2:
        return _cover_arity_failure(IntrinsicKind.COVER_SEEK, 2)
    cover_id, side = arguments
    if not isinstance(cover_id, IntegerValue) or not isinstance(side, StringValue):
        return _cover_type_failure(IntrinsicKind.COVER_SEEK)
    return _CoverIntrinsicResult(
        RecordValue("TakeCover", ("cover_id", "side"), (cover_id, side)),
        1,
    )


def _cover_arity_failure(intrinsic: IntrinsicKind, expected_arity: int) -> _CoverIntrinsicFailure:
    return _CoverIntrinsicFailure(
        VMFaultCode.CALL,
        f"{_cover_intrinsic_name(intrinsic)} expects {expected_arity} arguments",
    )


def _cover_type_failure(intrinsic: IntrinsicKind) -> _CoverIntrinsicFailure:
    return _CoverIntrinsicFailure(
        VMFaultCode.TYPE,
        f"{_cover_intrinsic_name(intrinsic)} received malformed observable records",
    )


def _cover_intrinsic_name(intrinsic: IntrinsicKind) -> str:
    return f"Cover.{intrinsic.name.removeprefix('COVER_').lower()}"


def _consume_cover_work(budgets: VMBudgets, resources: _ExecutionResources) -> bool:
    if resources.instructions >= budgets.instruction_limit:
        return False
    resources.instructions += 1
    return True


def _cover_value(value: RuntimeValue) -> _CoverValue | None:
    fields = _record_values(
        value,
        "Cover",
        ("cover_id", "end", "height", "integrity_basis_points", "slots", "start"),
    )
    if fields is None:
        return None
    cover_id, end, height, integrity, slots, start = fields
    if (
        not isinstance(cover_id, IntegerValue)
        or cover_id.value <= 0
        or not isinstance(height, StringValue)
        or height.value not in ("low", "high")
        or not isinstance(integrity, IntegerValue)
        or not 0 <= integrity.value <= 10_000
        or not isinstance(slots, ListValue)
    ):
        return None
    start_position = _cover_position(start)
    end_position = _cover_position(end)
    if start_position is None or end_position is None:
        return None
    return _CoverValue(
        cover_id.value,
        start_position,
        end_position,
        height.value,
        integrity.value,
        slots,
    )


def _cover_slot_value(value: RuntimeValue) -> _CoverSlotValue | None:
    fields = _record_values(value, "CoverSlot", ("position", "side", "slot_index"))
    if fields is None:
        return None
    position, side, slot_index = fields
    if (
        not isinstance(side, StringValue)
        or side.value not in ("left", "right")
        or not isinstance(slot_index, IntegerValue)
        or slot_index.value < 0
    ):
        return None
    parsed_position = _cover_position(position)
    if parsed_position is None:
        return None
    return _CoverSlotValue(parsed_position, side.value, slot_index.value)


def _contact_position(value: RuntimeValue) -> _CoverPosition | None:
    fields = _record_values(
        value,
        "Contact",
        (
            "age_ticks",
            "confidence_basis_points",
            "contact_id",
            "estimated_position",
            "uncertainty_radius",
        ),
    )
    if fields is None:
        return None
    age_ticks, confidence, contact_id, position, uncertainty = fields
    if (
        not isinstance(age_ticks, IntegerValue)
        or age_ticks.value < 0
        or not isinstance(confidence, IntegerValue)
        or not 0 <= confidence.value <= 10_000
        or not isinstance(contact_id, IntegerValue)
        or contact_id.value <= 0
        or not isinstance(uncertainty, QuantityValue)
        or uncertainty.value.dimension is not QuantityDimension.DISTANCE
        or uncertainty.value.value.numerator < 0
    ):
        return None
    return _cover_position(position)


def _cover_position(value: RuntimeValue) -> _CoverPosition | None:
    fields = _record_values(value, "Position", ("x", "y"))
    if fields is None:
        return None
    x, y = fields
    if (
        not isinstance(x, QuantityValue)
        or x.value.dimension is not QuantityDimension.DISTANCE
        or not isinstance(y, QuantityValue)
        or y.value.dimension is not QuantityDimension.DISTANCE
    ):
        return None
    return _CoverPosition(x.value.value, y.value.value)


def _record_values(
    value: RuntimeValue,
    type_name: str,
    field_names: tuple[str, ...],
) -> tuple[RuntimeValue, ...] | None:
    if not isinstance(value, RecordValue) or value.type_name != type_name:
        return None
    if value.field_names != field_names:
        return None
    return value.values


def _cover_exposure_basis_points(
    cover: _CoverValue,
    slot: _CoverSlotValue,
    threat_position: _CoverPosition,
) -> int:
    threat_side = _cover_side_for_position(cover, threat_position)
    if threat_side is None or threat_side == slot.side:
        return 10_000
    protection = 5_000 if cover.height == "low" else 7_500
    return 10_000 - protection * cover.integrity_basis_points // 10_000


def _cover_side_for_position(cover: _CoverValue, position: _CoverPosition) -> str | None:
    vector_x = _subtract_rationals(cover.end.x, cover.start.x)
    vector_y = _subtract_rationals(cover.end.y, cover.start.y)
    offset_x = _subtract_rationals(position.x, cover.start.x)
    offset_y = _subtract_rationals(position.y, cover.start.y)
    cross_numerator = (
        vector_x.numerator * offset_y.numerator * vector_y.denominator * offset_x.denominator
        - vector_y.numerator * offset_x.numerator * vector_x.denominator * offset_y.denominator
    )
    if cross_numerator > 0:
        return "left"
    if cross_numerator < 0:
        return "right"
    return None


def _manhattan_distance(left: _CoverPosition, right: _CoverPosition) -> ExactRational:
    x_distance = _absolute_rational(_subtract_rationals(left.x, right.x))
    y_distance = _absolute_rational(_subtract_rationals(left.y, right.y))
    return ExactRational(
        x_distance.numerator * y_distance.denominator
        + y_distance.numerator * x_distance.denominator,
        x_distance.denominator * y_distance.denominator,
    )


def _subtract_rationals(left: ExactRational, right: ExactRational) -> ExactRational:
    return ExactRational(
        left.numerator * right.denominator - right.numerator * left.denominator,
        left.denominator * right.denominator,
    )


def _absolute_rational(value: ExactRational) -> ExactRational:
    return ExactRational(abs(value.numerator), value.denominator)


def _is_safer_cover_candidate(
    candidate: _CoverCandidateScore,
    selected: _CoverCandidateScore,
) -> bool:
    if candidate.exposure_basis_points != selected.exposure_basis_points:
        return candidate.exposure_basis_points < selected.exposure_basis_points
    cost_comparison = _compare_rationals(candidate.route_cost, selected.route_cost)
    if cost_comparison != 0:
        return cost_comparison < 0
    return (candidate.cover_id, candidate.slot.slot_index) < (
        selected.cover_id,
        selected.slot.slot_index,
    )


def _cover_selection_trace(
    source_map_entry: InstructionSourceMapEntry,
    candidates: tuple[_CoverCandidateScore, ...],
) -> CoverSelectionTrace:
    ordered = _ordered_cover_candidates(candidates)
    if not ordered:
        return CoverSelectionTrace(source_map_entry, ())
    selected = ordered[0]
    traces = tuple(
        CoverCandidateTrace(
            candidate.cover_id,
            candidate.slot.slot_index,
            candidate.slot.side,
            candidate.exposure_basis_points,
            Quantity(QuantityDimension.DISTANCE, candidate.route_cost),
            (
                CoverCandidateTraceStatus.SELECTED
                if index == 0
                else CoverCandidateTraceStatus.REJECTED
            ),
            None if index == 0 else _cover_candidate_rejection_reason(candidate, selected),
        )
        for index, candidate in enumerate(ordered)
    )
    return CoverSelectionTrace(source_map_entry, traces)


def _ordered_cover_candidates(
    candidates: tuple[_CoverCandidateScore, ...],
) -> tuple[_CoverCandidateScore, ...]:
    ordered: list[_CoverCandidateScore] = []
    for candidate in candidates:
        insertion_index = len(ordered)
        while insertion_index > 0 and _is_safer_cover_candidate(
            candidate, ordered[insertion_index - 1]
        ):
            insertion_index -= 1
        ordered.insert(insertion_index, candidate)
    return tuple(ordered)


def _cover_candidate_rejection_reason(
    candidate: _CoverCandidateScore,
    selected: _CoverCandidateScore,
) -> CoverCandidateRejectionReason:
    if candidate.exposure_basis_points != selected.exposure_basis_points:
        return CoverCandidateRejectionReason.HIGHER_EXPOSURE
    if _compare_rationals(candidate.route_cost, selected.route_cost) != 0:
        return CoverCandidateRejectionReason.HIGHER_ROUTE_COST
    if candidate.cover_id != selected.cover_id:
        return CoverCandidateRejectionReason.HIGHER_COVER_ID
    if candidate.slot.slot_index != selected.slot.slot_index:
        return CoverCandidateRejectionReason.HIGHER_SLOT_INDEX
    raise AssertionError("cover selection trace has duplicate candidate ranks")


def _compare_rationals(left: ExactRational, right: ExactRational) -> int:
    difference = left.numerator * right.denominator - right.numerator * left.denominator
    return (difference > 0) - (difference < 0)


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
