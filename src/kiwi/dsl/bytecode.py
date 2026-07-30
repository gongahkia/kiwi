"""Versioned bytecode module metadata for the Kiwi DSL."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.dsl.source import SourceFileId

SOURCE_LANGUAGE_VERSION = 1
CORE_IR_VERSION = 1
BYTECODE_VERSION = 1


@dataclass(frozen=True, slots=True)
class FunctionId:
    """The canonical index of one bytecode function."""

    value: int

    def __post_init__(self) -> None:
        if not isinstance(self.value, int) or isinstance(self.value, bool) or self.value < 0:
            raise ValueError("function ID must be a non-negative integer")


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
