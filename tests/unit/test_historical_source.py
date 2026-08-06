from __future__ import annotations

from kiwi.domain.ids import EntityId
from kiwi.dsl.ids import ExpressionId, FunctionId
from kiwi.dsl.source import SourceFileId
from kiwi.replay.source_archive import (
    HistoricalPolicySource,
    HistoricalSourceFile,
    ReplaySourceArchive,
)
from kiwi.sim.policy_versions import PolicyVersion
from kiwi.ui.compile_output import compile_editor_source
from kiwi.ui.editor import EditorState
from kiwi.ui.historical_source import (
    HistoricalSourcePane,
    HistoricalSourceUnavailable,
    HistoricalSourceUnavailableCode,
    historical_source_pane,
)


def test_historical_source_pane_uses_archived_source_and_exact_expression_spans() -> None:
    archive, expression_id = _archive()

    pane = historical_source_pane(archive, EntityId(1), expression_id)

    assert isinstance(pane, HistoricalSourcePane)
    assert pane.source == archive.sources[0].source
    assert pane.expression_id == expression_id
    assert pane.highlighted_spans == tuple(
        sorted(
            {
                entry.span
                for entry in archive.policies[0].bytecode.source_map.entries
                if entry.expression_id == expression_id
            },
            key=lambda span: (span.start.value, span.end.value),
        )
    )


def test_historical_source_pane_reports_missing_policy_and_expression() -> None:
    archive, expression_id = _archive()

    missing_policy = historical_source_pane(archive, EntityId(2), expression_id)
    missing_expression = historical_source_pane(archive, EntityId(1), ExpressionId(99_999))

    assert isinstance(missing_policy, HistoricalSourceUnavailable)
    assert missing_policy.code is HistoricalSourceUnavailableCode.POLICY_NOT_RETAINED
    assert isinstance(missing_expression, HistoricalSourceUnavailable)
    assert missing_expression.code is HistoricalSourceUnavailableCode.EXPRESSION_NOT_RETAINED


def _archive() -> tuple[ReplaySourceArchive, ExpressionId]:
    output = compile_editor_source(
        SourceFileId("historical.dtr"),
        EditorState.from_text("fn choose(value: Int) -> Int = value"),
    )
    assert output.artifact is not None
    bytecode = output.artifact.bytecode
    policy = HistoricalPolicySource(
        EntityId(1),
        PolicyVersion.from_bytecode(bytecode, FunctionId(0)),
        FunctionId(0),
        bytecode,
    )
    return (
        ReplaySourceArchive(
            b"h" * 32,
            (HistoricalSourceFile(output.source, bytecode.header.source_language_version),),
            (policy,),
        ),
        bytecode.source_map.entries[0].expression_id,
    )
