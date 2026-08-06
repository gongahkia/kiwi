from __future__ import annotations

from kiwi.domain.ids import EntityId, EventId, PolicyInvocationId, TraceNodeId
from kiwi.dsl.bytecode import InstructionSourceMapEntry
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.source import SourceFile, SourceFileId, SourceSpan
from kiwi.replay.source_archive import (
    HistoricalPolicySource,
    HistoricalSourceFile,
    ReplaySourceArchive,
)
from kiwi.sim.events import EventKind
from kiwi.sim.policy_versions import PolicyVersion
from kiwi.trace.model import (
    CausalTrace,
    ConsequenceTrace,
    ExpressionEvaluationTrace,
    PolicyInvocationTrace,
    TraceConsequenceKind,
    TraceEdge,
    TraceEdgeId,
    TraceEdgeKind,
    TraceLevel,
    WorldEventTrace,
)
from kiwi.ui.compile_output import compile_editor_source
from kiwi.ui.editor import EditorState
from kiwi.ui.terminal_debrief import TerminalDebrief, terminal_debrief
from kiwi.ui.terminal_revision import (
    GuidedRevisionUnavailable,
    GuidedRevisionUnavailableCode,
    TerminalGuidedRevision,
    guided_source_revision,
)
from kiwi.ui.terminal_workbench import (
    TerminalWorkbench,
    WorkbenchPolicy,
    create_terminal_workbench,
)

SCOUT_FILE_ID = SourceFileId("examples/policies/terminal/scout.dtr")
ENEMY_FILE_ID = SourceFileId("enemy.dtr")
SCOUT_TEXT = "fn choose(value: Int) -> Int = value"


def test_guided_revision_prefers_editable_player_source_and_preserves_compilation() -> None:
    archive, trace, player_expression = _archive_and_trace()
    debrief = terminal_debrief(trace)
    workbench = _workbench().select_policy("scout").compile_selected().select_policy("breacher")

    assert isinstance(debrief, TerminalDebrief)
    result = guided_source_revision(debrief, trace, archive, workbench)

    assert isinstance(result, TerminalGuidedRevision)
    assert result.injury_node_id == TraceNodeId(7)
    assert result.historical_source.entity_id == EntityId(1)
    assert result.workbench.selected_policy.role == "scout"
    assert result.selected_span == player_expression.span
    assert result.workbench.editor.selected_text == _span_text(SCOUT_TEXT, player_expression.span)
    assert result.workbench.compile_output is not None
    assert result.workbench.compile_output.succeeded


def test_guided_revision_refuses_to_apply_historical_offsets_to_changed_source() -> None:
    archive, trace, _ = _archive_and_trace()
    debrief = terminal_debrief(trace)

    assert isinstance(debrief, TerminalDebrief)
    result = guided_source_revision(
        debrief,
        trace,
        archive,
        _workbench(scout_text="fn choose(value: Int) -> Int = value + 0"),
    )

    assert isinstance(result, GuidedRevisionUnavailable)
    assert result.code is GuidedRevisionUnavailableCode.CURRENT_SOURCE_CHANGED
    assert result.historical_source is not None
    assert result.historical_source.source.text == SCOUT_TEXT


def _archive_and_trace() -> tuple[ReplaySourceArchive, CausalTrace, InstructionSourceMapEntry]:
    player_output = compile_editor_source(SCOUT_FILE_ID, EditorState.from_text(SCOUT_TEXT))
    enemy_output = compile_editor_source(ENEMY_FILE_ID, EditorState.from_text(SCOUT_TEXT))
    assert player_output.artifact is not None
    assert enemy_output.artifact is not None
    player_bytecode = player_output.artifact.bytecode
    enemy_bytecode = enemy_output.artifact.bytecode
    player_expression = player_bytecode.source_map.entries[0]
    enemy_expression = enemy_bytecode.source_map.entries[0]
    archive = ReplaySourceArchive(
        b"a" * 32,
        (
            HistoricalSourceFile(
                enemy_output.source, enemy_bytecode.header.source_language_version
            ),
            HistoricalSourceFile(
                player_output.source, player_bytecode.header.source_language_version
            ),
        ),
        (
            HistoricalPolicySource(
                EntityId(1),
                PolicyVersion.from_bytecode(player_bytecode, FunctionId(0)),
                FunctionId(0),
                player_bytecode,
            ),
            HistoricalPolicySource(
                EntityId(2),
                PolicyVersion.from_bytecode(enemy_bytecode, FunctionId(0)),
                FunctionId(0),
                enemy_bytecode,
            ),
        ),
    )
    trace = CausalTrace(
        b"t" * 32,
        TraceLevel.FULL,
        (
            PolicyInvocationTrace(
                TraceNodeId(1),
                0,
                EntityId(1),
                PolicyInvocationId(1),
                b"p" * 32,
                FunctionId(0),
                b"m" * 32,
                "success",
            ),
            ExpressionEvaluationTrace(
                TraceNodeId(2),
                0,
                PolicyInvocationId(1),
                player_expression.expression_id,
                player_expression.span,
                "player value",
            ),
            WorldEventTrace(
                TraceNodeId(3), 0, EventId(2), EventKind.MOVEMENT_ROUTE_STARTED, "player advance"
            ),
            PolicyInvocationTrace(
                TraceNodeId(4),
                0,
                EntityId(2),
                PolicyInvocationId(2),
                b"e" * 32,
                FunctionId(0),
                b"n" * 32,
                "success",
            ),
            ExpressionEvaluationTrace(
                TraceNodeId(5),
                0,
                PolicyInvocationId(2),
                enemy_expression.expression_id,
                enemy_expression.span,
                "enemy value",
            ),
            WorldEventTrace(TraceNodeId(6), 1, EventId(1), EventKind.DAMAGE_APPLIED, "damage"),
            ConsequenceTrace(
                TraceNodeId(7),
                1,
                TraceConsequenceKind.INJURY,
                (EntityId(1),),
                EventId(1),
                "injury",
            ),
        ),
        (
            TraceEdge(TraceEdgeId(1), TraceNodeId(1), TraceNodeId(2), TraceEdgeKind.COMPUTED_FROM),
            TraceEdge(TraceEdgeId(2), TraceNodeId(2), TraceNodeId(3), TraceEdgeKind.CAUSED_EVENT),
            TraceEdge(TraceEdgeId(3), TraceNodeId(3), TraceNodeId(6), TraceEdgeKind.CONTRIBUTED_TO),
            TraceEdge(TraceEdgeId(4), TraceNodeId(4), TraceNodeId(5), TraceEdgeKind.COMPUTED_FROM),
            TraceEdge(TraceEdgeId(5), TraceNodeId(5), TraceNodeId(6), TraceEdgeKind.CAUSED_EVENT),
            TraceEdge(TraceEdgeId(6), TraceNodeId(6), TraceNodeId(7), TraceEdgeKind.CONTRIBUTED_TO),
        ),
    )
    return archive, trace, player_expression


def _workbench(*, scout_text: str = SCOUT_TEXT) -> TerminalWorkbench:
    return create_terminal_workbench(
        (
            WorkbenchPolicy(
                "breacher", "Breach", SourceFile(SourceFileId("breach.dtr"), SCOUT_TEXT)
            ),
            WorkbenchPolicy("medic", "Mender", SourceFile(SourceFileId("medic.dtr"), SCOUT_TEXT)),
            WorkbenchPolicy(
                "overwatch", "Scope", SourceFile(SourceFileId("scope.dtr"), SCOUT_TEXT)
            ),
            WorkbenchPolicy("scout", "Lark", SourceFile(SCOUT_FILE_ID, scout_text)),
        )
    ).open_workbench()


def _span_text(text: str, span: SourceSpan) -> str:
    return text.encode("utf-8")[span.start.value : span.end.value].decode("utf-8")
