from __future__ import annotations

import pytest

from kiwi.dsl.diagnostics import Diagnostic, DiagnosticSeverity, DiagnosticStage
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.ui.diagnostics import present_diagnostics


def test_diagnostics_project_to_canonical_multiline_inline_markers_and_panel_rows() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "one\ntwo\nthree")
    warning = Diagnostic(
        "W100_EXAMPLE",
        DiagnosticSeverity.WARNING,
        "empty location",
        source.span(ByteOffset(0), ByteOffset(0)),
        DiagnosticStage.LEXER,
    )
    error = Diagnostic(
        "E200_EXAMPLE",
        DiagnosticSeverity.ERROR,
        "multiline range",
        source.span(ByteOffset(2), ByteOffset(9)),
        DiagnosticStage.PARSER,
    )

    presentation = present_diagnostics(source, (error, warning))

    assert presentation.source_file_id == source.file_id
    assert tuple(
        (entry.diagnostic.code, entry.line, entry.column) for entry in presentation.panel
    ) == (("W100_EXAMPLE", 1, 1), ("E200_EXAMPLE", 1, 3))
    assert tuple(
        (marker.diagnostic.code, marker.line, marker.start_column, marker.end_column)
        for marker in presentation.inline
    ) == (
        ("W100_EXAMPLE", 1, 1, 1),
        ("E200_EXAMPLE", 1, 3, 4),
        ("E200_EXAMPLE", 2, 1, 4),
        ("E200_EXAMPLE", 3, 1, 2),
    )


def test_diagnostic_presentation_rejects_a_span_from_another_source() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "value")
    other = SourceFile(SourceFileId("other.dtr"), "value")
    diagnostic = Diagnostic(
        "E200_EXAMPLE",
        DiagnosticSeverity.ERROR,
        "wrong source",
        other.span(ByteOffset(0), ByteOffset(1)),
        DiagnosticStage.PARSER,
    )

    with pytest.raises(ValueError, match="belongs to a different source file"):
        present_diagnostics(source, (diagnostic,))
