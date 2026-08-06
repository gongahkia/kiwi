"""Safe source-revision guidance from a selected Terminal injury."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.ids import EntityId, TraceNodeId
from kiwi.dsl.source import SourceFile, SourceSpan
from kiwi.replay.source_archive import ReplaySourceArchive
from kiwi.trace.model import CausalTrace
from kiwi.ui.historical_source import HistoricalSourcePane
from kiwi.ui.terminal_debrief import TerminalDebrief, TerminalDebriefUnavailable
from kiwi.ui.terminal_workbench import TerminalFlowPhase, TerminalWorkbench
from kiwi.ui.trace_navigation import (
    TraceNavigationUnavailable,
    trace_to_historical_source,
)


class GuidedRevisionUnavailableCode(StrEnum):
    INJURY_NOT_RETAINED = "injury_not_retained"
    CURRENT_SOURCE_CHANGED = "current_source_changed"


@dataclass(frozen=True, slots=True)
class GuidedRevisionUnavailable:
    code: GuidedRevisionUnavailableCode
    historical_source: HistoricalSourcePane | None

    def __post_init__(self) -> None:
        if not isinstance(self.code, GuidedRevisionUnavailableCode):
            raise TypeError("guided revision unavailable result requires a code")
        if self.historical_source is not None and not isinstance(
            self.historical_source, HistoricalSourcePane
        ):
            raise TypeError("guided revision unavailable historical source is invalid")
        if (
            self.code is GuidedRevisionUnavailableCode.CURRENT_SOURCE_CHANGED
            and self.historical_source is None
        ):
            raise ValueError("changed current source requires historical source")


@dataclass(frozen=True, slots=True)
class TerminalGuidedRevision:
    injury_node_id: TraceNodeId
    historical_source: HistoricalSourcePane
    workbench: TerminalWorkbench
    selected_span: SourceSpan | None

    def __post_init__(self) -> None:
        if not isinstance(self.injury_node_id, TraceNodeId):
            raise TypeError("guided revision requires an injury trace node ID")
        if not isinstance(self.historical_source, HistoricalSourcePane):
            raise TypeError("guided revision requires historical source")
        if not isinstance(self.workbench, TerminalWorkbench):
            raise TypeError("guided revision requires a Terminal workbench")
        if self.workbench.phase is not TerminalFlowPhase.WORKBENCH:
            raise ValueError("guided revision requires an open Terminal workbench")
        if self.workbench.source.file_id != self.historical_source.source.file_id:
            raise ValueError("guided revision workbench source is not historical source")
        if self.workbench.source.text != self.historical_source.source.text:
            raise ValueError("guided revision must not map historical offsets to changed source")
        if self.selected_span is not None:
            if not isinstance(self.selected_span, SourceSpan):
                raise TypeError("guided revision selected span is invalid")
            if self.selected_span not in self.historical_source.highlighted_spans:
                raise ValueError("guided revision selected span is not historical provenance")
            expected = _span_text(self.workbench.source, self.selected_span)
            if self.workbench.editor.selected_text != expected:
                raise ValueError(
                    "guided revision editor selection does not match source provenance"
                )
        elif not self.workbench.editor.selection.is_empty:
            raise ValueError("guided revision without a span must leave no editor selection")


type GuidedRevisionResult = (
    TerminalGuidedRevision | GuidedRevisionUnavailable | TraceNavigationUnavailable
)


def guided_source_revision(
    debrief: TerminalDebrief,
    trace: CausalTrace,
    archive: ReplaySourceArchive,
    workbench: TerminalWorkbench,
) -> GuidedRevisionResult:
    """Focus the selected injury's unchanged player source without rewriting it."""
    if not isinstance(debrief, TerminalDebrief):
        raise TypeError("guided revision requires a Terminal debrief")
    if not isinstance(trace, CausalTrace):
        raise TypeError("guided revision requires a causal trace")
    if not isinstance(archive, ReplaySourceArchive):
        raise TypeError("guided revision requires a replay source archive")
    if not isinstance(workbench, TerminalWorkbench):
        raise TypeError("guided revision requires a Terminal workbench")
    if workbench.phase is not TerminalFlowPhase.WORKBENCH:
        raise ValueError("guided revision requires an open Terminal workbench")
    selected = debrief.select_injury(trace, debrief.selected_node_id)
    if isinstance(selected, TerminalDebriefUnavailable):
        return GuidedRevisionUnavailable(GuidedRevisionUnavailableCode.INJURY_NOT_RETAINED, None)
    pane = trace_to_historical_source(
        trace,
        archive,
        selected.selected_node_id,
        eligible_entity_ids=_editable_entities(archive, workbench),
    )
    if isinstance(pane, TraceNavigationUnavailable):
        return pane
    focused = _select_workbench_source(workbench, pane.source.file_id.value)
    if focused.source.text != pane.source.text:
        return GuidedRevisionUnavailable(GuidedRevisionUnavailableCode.CURRENT_SOURCE_CHANGED, pane)
    selected_span = pane.highlighted_spans[0] if pane.highlighted_spans else None
    return TerminalGuidedRevision(
        selected.selected_node_id,
        pane,
        focused.focus_source(selected_span),
        selected_span,
    )


def _editable_entities(
    archive: ReplaySourceArchive, workbench: TerminalWorkbench
) -> tuple[EntityId, ...]:
    source_file_ids = tuple(policy.source.file_id for policy in workbench.policies)
    return tuple(
        policy.entity_id
        for policy in archive.policies
        if policy.bytecode.header.source_file_id in source_file_ids
    )


def _select_workbench_source(workbench: TerminalWorkbench, file_id: str) -> TerminalWorkbench:
    for policy in workbench.policies:
        if policy.source.file_id.value == file_id:
            return workbench.select_policy(policy.role)
    raise AssertionError("eligible historical source has no Terminal workbench policy")


def _span_text(source: SourceFile, span: SourceSpan) -> str:
    return source.text.encode("utf-8")[span.start.value : span.end.value].decode("utf-8")
