"""Headless deterministic projections of structured DSL diagnostics for the UI."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.dsl.diagnostics import Diagnostic
from kiwi.dsl.source import SourceFile, SourceFileId


@dataclass(frozen=True, slots=True)
class InlineDiagnostic:
    """One line-local source range for an inline diagnostic marker."""

    diagnostic: Diagnostic
    line: int
    start_column: int
    end_column: int

    def __post_init__(self) -> None:
        if not isinstance(self.diagnostic, Diagnostic):
            raise TypeError("inline diagnostic requires a diagnostic")
        _require_positive(self.line, "inline diagnostic line")
        _require_positive(self.start_column, "inline diagnostic start column")
        _require_positive(self.end_column, "inline diagnostic end column")
        if self.end_column < self.start_column:
            raise ValueError("inline diagnostic end column precedes start column")


@dataclass(frozen=True, slots=True)
class PanelDiagnostic:
    """One structured diagnostic positioned for a compact list panel."""

    diagnostic: Diagnostic
    line: int
    column: int

    def __post_init__(self) -> None:
        if not isinstance(self.diagnostic, Diagnostic):
            raise TypeError("panel diagnostic requires a diagnostic")
        _require_positive(self.line, "panel diagnostic line")
        _require_positive(self.column, "panel diagnostic column")


@dataclass(frozen=True, slots=True)
class DiagnosticPresentation:
    """Canonical inline markers and panel entries for one immutable source file."""

    source_file_id: SourceFileId
    inline: tuple[InlineDiagnostic, ...]
    panel: tuple[PanelDiagnostic, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.source_file_id, SourceFileId):
            raise TypeError("diagnostic presentation requires a source file ID")
        if not isinstance(self.inline, tuple) or any(
            not isinstance(marker, InlineDiagnostic) for marker in self.inline
        ):
            raise TypeError("diagnostic presentation inline entries must be inline diagnostics")
        if not isinstance(self.panel, tuple) or any(
            not isinstance(entry, PanelDiagnostic) for entry in self.panel
        ):
            raise TypeError("diagnostic presentation panel entries must be panel diagnostics")


def present_diagnostics(
    source: SourceFile,
    diagnostics: tuple[Diagnostic, ...],
) -> DiagnosticPresentation:
    """Project diagnostics into canonical source-line and panel presentation data."""
    if not isinstance(source, SourceFile):
        raise TypeError("diagnostic presentation requires a source file")
    if not isinstance(diagnostics, tuple):
        raise TypeError("diagnostics must be a tuple")
    if any(not isinstance(diagnostic, Diagnostic) for diagnostic in diagnostics):
        raise TypeError("diagnostics must contain diagnostics")
    ordered = tuple(sorted(diagnostics, key=_diagnostic_key))
    inline: list[InlineDiagnostic] = []
    panel: list[PanelDiagnostic] = []
    lines = source.text.split("\n")
    for diagnostic in ordered:
        start, end = source.positions_of(diagnostic.primary_span)
        panel.append(PanelDiagnostic(diagnostic, start.line, start.column))
        for line in range(start.line, end.line + 1):
            line_length = len(lines[line - 1])
            start_column = start.column if line == start.line else 1
            end_column = end.column if line == end.line else line_length + 1
            inline.append(InlineDiagnostic(diagnostic, line, start_column, end_column))
    return DiagnosticPresentation(source.file_id, tuple(inline), tuple(panel))


def _diagnostic_key(diagnostic: Diagnostic) -> tuple[int, int, str, str, str]:
    return (
        diagnostic.primary_span.start.value,
        diagnostic.primary_span.end.value,
        diagnostic.code,
        diagnostic.stage.value,
        diagnostic.message,
    )


def _require_positive(value: int, name: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise ValueError(f"{name} must be a positive integer")
