"""Deterministic compilation from typed core IR to Kiwi bytecode."""

from __future__ import annotations

from kiwi.dsl.bytecode import (
    BytecodeFunction,
    BytecodeHeader,
    BytecodeInstruction,
    BytecodeModule,
    Call,
    ConstantPoolBuilder,
    InstructionIndex,
    Jump,
    JumpIfFalse,
    LoadLocal,
    LocalSlot,
    Negate,
    PushConstant,
    PushFunction,
    Return,
    StoreLocal,
    canonical_function_table,
)
from kiwi.dsl.core_ir import (
    CoreBoolean,
    CoreCall,
    CoreDefinition,
    CoreExpression,
    CoreIf,
    CoreInteger,
    CoreLet,
    CoreModule,
    CoreNegate,
    CoreReference,
)
from kiwi.dsl.ids import DefinitionId, FunctionId, SymbolId
from kiwi.dsl.runtime_values import BooleanValue, IntegerValue


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
    functions = tuple(
        _FunctionCompiler(constants, global_functions).compile(
            _definition_for_id(module.definitions, entry.definition_id),
            entry.function_id,
        )
        for entry in function_table.entries
    )
    return BytecodeModule(header, constants.freeze(), function_table, functions)


class _FunctionCompiler:
    def __init__(
        self,
        constants: ConstantPoolBuilder,
        global_functions: tuple[tuple[SymbolId, FunctionId], ...],
    ) -> None:
        self._constants = constants
        self._global_functions = global_functions
        self._instructions: list[BytecodeInstruction] = []
        self._locals: list[tuple[SymbolId, LocalSlot]] = []
        self._next_slot = 0

    def compile(self, definition: CoreDefinition, function_id: FunctionId) -> BytecodeFunction:
        for parameter in definition.parameters:
            self._locals.append((parameter.symbol_id, LocalSlot(self._next_slot)))
            self._next_slot += 1
        self._compile_expression(definition.body)
        self._instructions.append(Return())
        return BytecodeFunction(
            function_id,
            definition.definition_id,
            definition.name,
            len(definition.parameters),
            self._next_slot,
            definition.return_type,
            tuple(self._instructions),
        )

    def _compile_expression(self, expression: CoreExpression) -> None:
        if isinstance(expression, CoreInteger):
            self._instructions.append(
                PushConstant(self._constants.intern(IntegerValue(expression.value)))
            )
            return
        if isinstance(expression, CoreBoolean):
            self._instructions.append(
                PushConstant(self._constants.intern(BooleanValue(expression.value)))
            )
            return
        if isinstance(expression, CoreReference):
            slot = _slot_for(self._locals, expression.symbol_id)
            if slot is not None:
                self._instructions.append(LoadLocal(slot))
                return
            self._instructions.append(
                PushFunction(_function_for(self._global_functions, expression.symbol_id))
            )
            return
        if isinstance(expression, CoreNegate):
            self._compile_expression(expression.operand)
            self._instructions.append(Negate())
            return
        if isinstance(expression, CoreCall):
            self._compile_expression(expression.callee)
            for argument in expression.arguments:
                self._compile_expression(argument)
            self._instructions.append(Call(len(expression.arguments)))
            return
        if isinstance(expression, CoreLet):
            slot = LocalSlot(self._next_slot)
            self._next_slot += 1
            self._locals.append((expression.symbol_id, slot))
            self._compile_expression(expression.value)
            self._instructions.append(StoreLocal(slot))
            self._compile_expression(expression.body)
            return
        if isinstance(expression, CoreIf):
            self._compile_expression(expression.condition)
            branch_index = len(self._instructions)
            self._instructions.append(JumpIfFalse(InstructionIndex(0)))
            self._compile_expression(expression.then_branch)
            end_jump_index = len(self._instructions)
            self._instructions.append(Jump(InstructionIndex(0)))
            else_start = InstructionIndex(len(self._instructions))
            self._instructions[branch_index] = JumpIfFalse(else_start)
            self._compile_expression(expression.else_branch)
            end = InstructionIndex(len(self._instructions))
            self._instructions[end_jump_index] = Jump(end)
            return
        raise TypeError(f"unsupported core expression: {type(expression).__name__}")


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
