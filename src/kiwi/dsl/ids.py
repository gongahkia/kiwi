"""Stable identifiers assigned by the DSL compiler."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class DefinitionId:
    """The canonical identity of a declared top-level definition."""

    value: int

    def __post_init__(self) -> None:
        if not isinstance(self.value, int) or isinstance(self.value, bool) or self.value < 0:
            raise ValueError("definition ID must be a non-negative integer")


@dataclass(frozen=True, slots=True)
class SymbolId:
    """The canonical identity of a resolved lexical binding."""

    value: int

    def __post_init__(self) -> None:
        if not isinstance(self.value, int) or isinstance(self.value, bool) or self.value < 0:
            raise ValueError("symbol ID must be a non-negative integer")
