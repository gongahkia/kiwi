"""Structured diagnostics emitted by Kiwi DSL compiler stages."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.dsl.source import SourceSpan


class DiagnosticSeverity(StrEnum):
    """The player-visible severity of a diagnostic."""

    ERROR = "error"
    WARNING = "warning"


class DiagnosticStage(StrEnum):
    """Compiler stages that emit player-visible diagnostics."""

    LEXER = "lexer"
    PARSER = "parser"
    RESOLVER = "resolver"
    CHECKER = "checker"


@dataclass(frozen=True, slots=True)
class DiagnosticLabel:
    """One labelled secondary source range."""

    span: SourceSpan
    message: str

    def __post_init__(self) -> None:
        if not self.message:
            raise ValueError("diagnostic label message must not be empty")


@dataclass(frozen=True, slots=True)
class SuggestedEdit:
    """An optional source replacement a client may offer to the player."""

    span: SourceSpan
    replacement: str
    message: str

    def __post_init__(self) -> None:
        if not self.message:
            raise ValueError("suggested edit message must not be empty")


@dataclass(frozen=True, slots=True)
class Diagnostic:
    """A stable, source-linked compiler diagnostic."""

    code: str
    severity: DiagnosticSeverity
    message: str
    primary_span: SourceSpan
    stage: DiagnosticStage
    secondary_labels: tuple[DiagnosticLabel, ...] = ()
    notes: tuple[str, ...] = ()
    suggested_edit: SuggestedEdit | None = None

    def __post_init__(self) -> None:
        if not self.code:
            raise ValueError("diagnostic code must not be empty")
        if not self.message:
            raise ValueError("diagnostic message must not be empty")
        if any(not note for note in self.notes):
            raise ValueError("diagnostic notes must not be empty")
