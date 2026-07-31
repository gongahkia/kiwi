"""Deterministic compilation from typed core IR to Kiwi bytecode."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.dsl.bytecode import (
    BuildRecord,
    BuildSome,
    BytecodeFunction,
    BytecodeHeader,
    BytecodeInstruction,
    BytecodeModule,
    BytecodeSourceMap,
    Call,
    ConstantPoolBuilder,
    InstructionIndex,
    InstructionSourceMapEntry,
    Jump,
    JumpIfFalse,
    JumpIfNone,
    LoadField,
    LoadLocal,
    LocalSlot,
    Negate,
    Pop,
    PushConstant,
    PushFunction,
    PushNone,
    Return,
    StoreLocal,
    TraceExpression,
    UnwrapSome,
    canonical_function_table,
)
from kiwi.dsl.core_ir import (
    CoreBoolean,
    CoreCall,
    CoreDefinition,
    CoreExpression,
    CoreFieldAccess,
    CoreIf,
    CoreInteger,
    CoreLet,
    CoreMatch,
    CoreMatchNoneArm,
    CoreMatchSomeArm,
    CoreModule,
    CoreNegate,
    CoreNone,
    CoreQuantity,
    CoreRecord,
    CoreReference,
    CoreSome,
    CoreString,
)
from kiwi.dsl.ids import DefinitionId, ExpressionId, FunctionId, SymbolId
from kiwi.dsl.runtime_values import BooleanValue, IntegerValue, QuantityValue, StringValue
from kiwi.dsl.source import SourceSpan


def compile_core(module: CoreModule, header: BytecodeHeader) -> BytecodeModule:
    """Compile a source-matched core module using only explicit orderings."""
    if header.source_file_id != module.span.file_id:
        raise ValueError("bytecode header source file does not match core module")
    function_table = canonical_function_table(module.definitions)
    constants = ConstantPoolBuilder()
    global_functions = tuple(
        (
            _definition_for_id(module.definitions, entry.definition_id).symbol_id,
            entry.function_id,
        )
        for entry in function_table.entries
    )
    compiled_functions = tuple(
        _FunctionCompiler(constants, global_functions).compile(
            _definition_for_id(module.definitions, entry.definition_id),
            entry.function_id,
        )
        for entry in function_table.entries
    )
    functions = tuple(compiled.function for compiled in compiled_functions)
    source_map = BytecodeSourceMap(
        tuple(entry for compiled in compiled_functions for entry in compiled.source_map_entries)
    )
    return BytecodeModule(header, constants.freeze(), function_table, functions, source_map)


@dataclass(frozen=True, slots=True)
class _CompiledFunction:
    function: BytecodeFunction
    source_map_entries: tuple[InstructionSourceMapEntry, ...]


class _FunctionCompiler:
    def __init__(
        self,
        constants: ConstantPoolBuilder,
        global_functions: tuple[tuple[SymbolId, FunctionId], ...],
    ) -> None:
        self._constants = constants
        self._global_functions = global_functions
        self._instructions: list[BytecodeInstruction] = []
        self._origins: list[tuple[ExpressionId, SourceSpan]] = []
        self._locals: list[tuple[SymbolId, LocalSlot]] = []
        self._next_slot = 0

    def compile(self, definition: CoreDefinition, function_id: FunctionId) -> _CompiledFunction:
        for parameter in definition.parameters:
            self._locals.append((parameter.symbol_id, LocalSlot(self._next_slot)))
            self._next_slot += 1
        self._compile_expression(definition.body)
        self._emit(Return(), definition.body)
        function = BytecodeFunction(
            function_id,
            definition.definition_id,
            definition.name,
            len(definition.parameters),
            self._next_slot,
            definition.return_type,
            tuple(self._instructions),
        )
        return _CompiledFunction(
            function,
            tuple(
                InstructionSourceMapEntry(function_id, InstructionIndex(index), expression_id, span)
                for index, (expression_id, span) in enumerate(self._origins)
            ),
        )

    def _compile_expression(self, expression: CoreExpression) -> None:
        self._emit(TraceExpression(expression.expression_id), expression)
        if isinstance(expression, CoreInteger):
            self._emit(
                PushConstant(self._constants.intern(IntegerValue(expression.value))),
                expression,
            )
            return
        if isinstance(expression, CoreBoolean):
            self._emit(
                PushConstant(self._constants.intern(BooleanValue(expression.value))),
                expression,
            )
            return
        if isinstance(expression, CoreString):
            self._emit(
                PushConstant(self._constants.intern(StringValue(expression.value))),
                expression,
            )
            return
        if isinstance(expression, CoreQuantity):
            self._emit(
                PushConstant(self._constants.intern(QuantityValue(expression.value))),
                expression,
            )
            return
        if isinstance(expression, CoreSome):
            self._compile_expression(expression.value)
            self._emit(BuildSome(), expression)
            return
        if isinstance(expression, CoreNone):
            self._emit(PushNone(), expression)
            return
        if isinstance(expression, CoreMatch):
            some_arm, none_arm = _option_match_arms(expression)
            self._compile_expression(expression.subject)
            none_jump_index = len(self._instructions)
            self._emit(JumpIfNone(InstructionIndex(0)), expression)
            some_slot = LocalSlot(self._next_slot)
            self._next_slot += 1
            self._locals.append((some_arm.symbol_id, some_slot))
            self._emit(UnwrapSome(), expression)
            self._emit(StoreLocal(some_slot), expression)
            self._compile_expression(some_arm.body)
            end_jump_index = len(self._instructions)
            self._emit(Jump(InstructionIndex(0)), expression)
            none_start = InstructionIndex(len(self._instructions))
            self._instructions[none_jump_index] = JumpIfNone(none_start)
            self._emit(Pop(), expression)
            self._compile_expression(none_arm.body)
            end = InstructionIndex(len(self._instructions))
            self._instructions[end_jump_index] = Jump(end)
            return
        if isinstance(expression, CoreRecord):
            for field in expression.fields:
                self._compile_expression(field.value)
            self._emit(
                BuildRecord(
                    expression.type_name,
                    tuple(field.name for field in expression.fields),
                ),
                expression,
            )
            return
        if isinstance(expression, CoreReference):
            slot = _slot_for(self._locals, expression.symbol_id)
            if slot is not None:
                self._emit(LoadLocal(slot), expression)
                return
            self._emit(
                PushFunction(_function_for(self._global_functions, expression.symbol_id)),
                expression,
            )
            return
        if isinstance(expression, CoreNegate):
            self._compile_expression(expression.operand)
            self._emit(Negate(), expression)
            return
        if isinstance(expression, CoreCall):
            self._compile_expression(expression.callee)
            for argument in expression.arguments:
                self._compile_expression(argument)
            self._emit(Call(len(expression.arguments)), expression)
            return
        if isinstance(expression, CoreFieldAccess):
            self._compile_expression(expression.record)
            self._emit(LoadField(expression.field_name), expression)
            return
        if isinstance(expression, CoreLet):
            slot = LocalSlot(self._next_slot)
            self._next_slot += 1
            self._locals.append((expression.symbol_id, slot))
            self._compile_expression(expression.value)
            self._emit(StoreLocal(slot), expression)
            self._compile_expression(expression.body)
            return
        if isinstance(expression, CoreIf):
            self._compile_expression(expression.condition)
            branch_index = len(self._instructions)
            self._emit(JumpIfFalse(InstructionIndex(0)), expression)
            self._compile_expression(expression.then_branch)
            end_jump_index = len(self._instructions)
            self._emit(Jump(InstructionIndex(0)), expression)
            else_start = InstructionIndex(len(self._instructions))
            self._instructions[branch_index] = JumpIfFalse(else_start)
            self._compile_expression(expression.else_branch)
            end = InstructionIndex(len(self._instructions))
            self._instructions[end_jump_index] = Jump(end)
            return
        raise TypeError(f"unsupported core expression: {type(expression).__name__}")

    def _emit(self, instruction: BytecodeInstruction, expression: CoreExpression) -> None:
        self._instructions.append(instruction)
        self._origins.append((expression.expression_id, expression.span))


def _definition_for_id(
    definitions: tuple[CoreDefinition, ...],
    definition_id: DefinitionId,
) -> CoreDefinition:
    for definition in definitions:
        if definition.definition_id == definition_id:
            return definition
    raise AssertionError("function table references no core definition")


def _slot_for(
    locals_: list[tuple[SymbolId, LocalSlot]],
    symbol_id: SymbolId,
) -> LocalSlot | None:
    for candidate_symbol, slot in reversed(locals_):
        if candidate_symbol == symbol_id:
            return slot
    return None


def _function_for(
    functions: tuple[tuple[SymbolId, FunctionId], ...],
    symbol_id: SymbolId,
) -> FunctionId:
    for candidate_symbol, function_id in functions:
        if candidate_symbol == symbol_id:
            return function_id
    raise AssertionError("core reference has no local slot or global function")


def _option_match_arms(expression: CoreMatch) -> tuple[CoreMatchSomeArm, CoreMatchNoneArm]:
    some_arm: CoreMatchSomeArm | None = None
    none_arm: CoreMatchNoneArm | None = None
    for arm in expression.arms:
        if isinstance(arm, CoreMatchSomeArm):
            some_arm = arm
        else:
            none_arm = arm
    if some_arm is None or none_arm is None:
        raise AssertionError("checked Option match is not exhaustive")
    return some_arm, none_arm
