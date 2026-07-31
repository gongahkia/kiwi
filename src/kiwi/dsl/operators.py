"""Closed source and bytecode identifiers for domain binary operations."""

from __future__ import annotations

from enum import IntEnum


class BinaryOperator(IntEnum):
    """Stable encoded operations for exact domain values."""

    ADD = 1
    SUBTRACT = 2
    LESS = 3
    LESS_EQUAL = 4
    GREATER = 5
    GREATER_EQUAL = 6


def render_binary_operator(operator: BinaryOperator) -> str:
    """Return the exact source spelling for one closed operator."""
    match operator:
        case BinaryOperator.ADD:
            return "+"
        case BinaryOperator.SUBTRACT:
            return "-"
        case BinaryOperator.LESS:
            return "<"
        case BinaryOperator.LESS_EQUAL:
            return "<="
        case BinaryOperator.GREATER:
            return ">"
        case BinaryOperator.GREATER_EQUAL:
            return ">="
