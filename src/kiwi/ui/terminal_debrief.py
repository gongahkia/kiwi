"""Deterministic injury-consequence selection for the Terminal debrief."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from kiwi.domain.ids import EntityId, TraceNodeId
from kiwi.trace.model import CausalTrace, ConsequenceTrace, TraceConsequenceKind, trace_record_id
from kiwi.ui.causal_chain import CausalChainPanel, CausalPanelUnavailable, causal_chain_panel


class TerminalDebriefUnavailableCode(StrEnum):
    NO_INJURY_RETAINED = "no_injury_retained"
    INJURY_NOT_RETAINED = "injury_not_retained"


@dataclass(frozen=True, slots=True)
class TerminalDebriefUnavailable:
    code: TerminalDebriefUnavailableCode

    def __post_init__(self) -> None:
        if not isinstance(self.code, TerminalDebriefUnavailableCode):
            raise TypeError("Terminal debrief unavailable result requires a code")


@dataclass(frozen=True, slots=True)
class InjuryConsequence:
    node_id: TraceNodeId
    tick: int
    subject_entity_ids: tuple[EntityId, ...]
    summary: str

    def __post_init__(self) -> None:
        if not isinstance(self.node_id, TraceNodeId):
            raise TypeError("injury consequence requires a trace node ID")
        if not isinstance(self.tick, int) or isinstance(self.tick, bool) or self.tick < 0:
            raise ValueError("injury consequence tick must be non-negative")
        if not isinstance(self.subject_entity_ids, tuple) or any(
            not isinstance(entity_id, EntityId) for entity_id in self.subject_entity_ids
        ):
            raise TypeError("injury consequence subjects must be immutable entity IDs")
        if tuple(entity_id.value for entity_id in self.subject_entity_ids) != tuple(
            sorted(entity_id.value for entity_id in self.subject_entity_ids)
        ) or len(set(self.subject_entity_ids)) != len(self.subject_entity_ids):
            raise ValueError("injury consequence subjects must be canonical")
        if not isinstance(self.summary, str) or not self.summary:
            raise ValueError("injury consequence summary must be non-empty")


@dataclass(frozen=True, slots=True)
class TerminalDebrief:
    injuries: tuple[InjuryConsequence, ...]
    selected_node_id: TraceNodeId
    chain: CausalChainPanel

    def __post_init__(self) -> None:
        if not isinstance(self.injuries, tuple) or not self.injuries:
            raise ValueError("Terminal debrief requires retained injuries")
        if any(not isinstance(injury, InjuryConsequence) for injury in self.injuries):
            raise TypeError("Terminal debrief injuries are invalid")
        keys = tuple((injury.tick, injury.node_id.value) for injury in self.injuries)
        if keys != tuple(sorted(keys)) or len({injury.node_id for injury in self.injuries}) != len(
            self.injuries
        ):
            raise ValueError("Terminal debrief injuries must be canonical")
        if self.selected_node_id not in tuple(injury.node_id for injury in self.injuries):
            raise ValueError("Terminal debrief selection is unavailable")
        if (
            not isinstance(self.chain, CausalChainPanel)
            or self.chain.detail.event.node_id != self.selected_node_id
        ):
            raise ValueError("Terminal debrief chain does not match selection")

    def select_injury(
        self, trace: CausalTrace, node_id: TraceNodeId
    ) -> TerminalDebrief | TerminalDebriefUnavailable:
        if not isinstance(trace, CausalTrace):
            raise TypeError("Terminal debrief selection requires a causal trace")
        if not isinstance(node_id, TraceNodeId):
            raise TypeError("Terminal debrief selection requires a trace node ID")
        retained = tuple(
            InjuryConsequence(
                trace_record_id(record), record.tick, record.subject_entity_ids, record.summary
            )
            for record in trace.records
            if isinstance(record, ConsequenceTrace) and record.kind is TraceConsequenceKind.INJURY
        )
        if (
            node_id not in tuple(injury.node_id for injury in self.injuries)
            or retained != self.injuries
        ):
            return TerminalDebriefUnavailable(TerminalDebriefUnavailableCode.INJURY_NOT_RETAINED)
        panel = causal_chain_panel(trace, node_id)
        if isinstance(panel, CausalPanelUnavailable):
            return TerminalDebriefUnavailable(TerminalDebriefUnavailableCode.INJURY_NOT_RETAINED)
        return replace(self, selected_node_id=node_id, chain=panel)


type TerminalDebriefResult = TerminalDebrief | TerminalDebriefUnavailable


def terminal_debrief(trace: CausalTrace) -> TerminalDebriefResult:
    """Select the first retained injury and its causal explanation for debrief."""
    if not isinstance(trace, CausalTrace):
        raise TypeError("Terminal debrief requires a causal trace")
    injuries = tuple(
        InjuryConsequence(
            trace_record_id(record), record.tick, record.subject_entity_ids, record.summary
        )
        for record in trace.records
        if isinstance(record, ConsequenceTrace) and record.kind is TraceConsequenceKind.INJURY
    )
    if not injuries:
        return TerminalDebriefUnavailable(TerminalDebriefUnavailableCode.NO_INJURY_RETAINED)
    panel = causal_chain_panel(trace, injuries[0].node_id)
    if isinstance(panel, CausalPanelUnavailable):
        return TerminalDebriefUnavailable(TerminalDebriefUnavailableCode.INJURY_NOT_RETAINED)
    return TerminalDebrief(injuries, injuries[0].node_id, panel)
