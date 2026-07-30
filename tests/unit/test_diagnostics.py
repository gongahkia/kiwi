from __future__ import annotations

from dataclasses import FrozenInstanceError

import pytest

from kiwi.dsl.diagnostics import (
    Diagnostic,
    DiagnosticLabel,
    DiagnosticSeverity,
    DiagnosticStage,
    SuggestedEdit,
)
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId


def test_diagnostic_retains_structured_source_context() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "a b")
    primary = source.span(ByteOffset(0), ByteOffset(1))
    secondary = source.span(ByteOffset(2), ByteOffset(3))
    diagnostic = Diagnostic(
        "E200_EXAMPLE",
        DiagnosticSeverity.ERROR,
        "example failure",
        primary,
        DiagnosticStage.PARSER,
        secondary_labels=(DiagnosticLabel(secondary, "related input"),),
        notes=("try another form",),
        suggested_edit=SuggestedEdit(primary, "x", "replace this value"),
    )

    assert diagnostic.code == "E200_EXAMPLE"
    assert diagnostic.secondary_labels[0].span == secondary
    assert diagnostic.suggested_edit == SuggestedEdit(primary, "x", "replace this value")


def test_diagnostics_are_immutable_and_validate_required_text() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "x")
    span = source.span(ByteOffset(0), ByteOffset(1))
    diagnostic = Diagnostic(
        "E200_EXAMPLE",
        DiagnosticSeverity.ERROR,
        "example failure",
        span,
        DiagnosticStage.PARSER,
    )

    with pytest.raises(FrozenInstanceError):
        diagnostic.message = "changed"  # type: ignore[misc]
    with pytest.raises(ValueError, match="code"):
        Diagnostic("", DiagnosticSeverity.ERROR, "message", span, DiagnosticStage.PARSER)
    with pytest.raises(ValueError, match="label message"):
        DiagnosticLabel(span, "")
    with pytest.raises(ValueError, match="suggested edit message"):
        SuggestedEdit(span, "x", "")
