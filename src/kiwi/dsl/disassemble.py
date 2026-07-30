"""Stable headless rendering for Kiwi bytecode modules."""

from __future__ import annotations

from kiwi.dsl.bytecode import (
    BytecodeInstruction,
    BytecodeModule,
    Call,
    Jump,
    JumpIfFalse,
    LoadLocal,
    Negate,
    PushConstant,
    PushFunction,
    Return,
    StoreLocal,
)
from kiwi.dsl.runtime_values import BooleanValue, IntegerValue, UnitValue
from kiwi.dsl.types import render_type


def disassemble(module: BytecodeModule) -> str:
    """Render a bytecode module without executing or mutating it."""
    header = module.header
    lines = [
        "BytecodeModule "
        f"source={header.source_file_id.value!r} "
        f"language={header.source_language_version} core={header.core_ir_version} "
        f"bytecode={header.bytecode_version}",
        "  constants:",
    ]
    for index, constant in enumerate(module.constants.values):
        lines.append(f"    {index}: {_format_constant(constant)}")
    lines.append("  function_table:")
    for entry in module.function_table.entries:
        lines.append(
            f"    {entry.function_id.value}: definition={entry.definition_id.value} "
            f"name={entry.name!r} arity={entry.arity}"
        )
    lines.append("  functions:")
    for function in module.functions:
        lines.append(
            f"    Function {function.function_id.value} definition={function.definition_id.value} "
            f"name={function.name!r} arity={function.arity} locals={function.local_slot_count} "
            f"return={render_type(function.return_type)}"
        )
        for index, instruction in enumerate(function.instructions):
            lines.append(f"      {index:04d} {_format_instruction(instruction)}")
    return "\n".join(lines)


def _format_constant(constant: IntegerValue | BooleanValue | UnitValue) -> str:
    if isinstance(constant, IntegerValue):
        return f"Integer({constant.value})"
    if isinstance(constant, BooleanValue):
        return f"Boolean({str(constant.value).lower()})"
    return "Unit"


def _format_instruction(instruction: BytecodeInstruction) -> str:
    if isinstance(instruction, PushConstant):
        return f"PUSH_CONSTANT {instruction.constant_id.value}"
    if isinstance(instruction, PushFunction):
        return f"PUSH_FUNCTION {instruction.function_id.value}"
    if isinstance(instruction, LoadLocal):
        return f"LOAD_LOCAL {instruction.slot.value}"
    if isinstance(instruction, StoreLocal):
        return f"STORE_LOCAL {instruction.slot.value}"
    if isinstance(instruction, Negate):
        return "NEGATE"
    if isinstance(instruction, Call):
        return f"CALL {instruction.argument_count}"
    if isinstance(instruction, Jump):
        return f"JUMP {instruction.target.value}"
    if isinstance(instruction, JumpIfFalse):
        return f"JUMP_IF_FALSE {instruction.target.value}"
    if isinstance(instruction, Return):
        return "RETURN"
    return f"TRACE_EXPRESSION {instruction.expression_id.value}"
