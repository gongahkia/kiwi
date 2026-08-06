"""Deterministic injury-consequence selection for the Glasshouse debrief."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from kiwi.domain.ids import EntityId, TraceNodeId
from kiwi.trace.model import CausalTrace, ConsequenceTrace, TraceConsequenceKind, trace_record_id
from kiwi.ui.causal_chain import CausalChainPanel, CausalPanelUnavailable, causal_chain_panel


class GlasshouseDebriefUnavailableCode(StrEnum):
    NO_INJURY_RETAINED = "no_injury_retained"
    INJURY_NOT_RETAINED = "injury_not_retained"


@dataclass(frozen=True, slots=True)
class GlasshouseDebriefUnavailable:
    code: GlasshouseDebriefUnavailableCode

    def __post_init__(self) -> None:
        if not isinstance(self.code, GlasshouseDebriefUnavailableCode):
            raise TypeError("Glasshouse debrief unavailable result requires a code")


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
class GlasshouseDebrief:
    injuries: tuple[InjuryConsequence, ...]
    selected_node_id: TraceNodeId
    chain: CausalChainPanel

    def __post_init__(self) -> None:
        if not isinstance(self.injuries, tuple) or not self.injuries:
            raise ValueError("Glasshouse debrief requires retained injuries")
        if any(not isinstance(injury, InjuryConsequence) for injury in self.injuries):
            raise TypeError("Glasshouse debrief injuries are invalid")
        keys = tuple((injury.tick, injury.node_id.value) for injury in self.injuries)
        if keys != tuple(sorted(keys)) or len({injury.node_id for injury in self.injuries}) != len(
            self.injuries
        ):
            raise ValueError("Glasshouse debrief injuries must be canonical")
        if self.selected_node_id not in tuple(injury.node_id for injury in self.injuries):
            raise ValueError("Glasshouse debrief selection is unavailable")
        if (
            not isinstance(self.chain, CausalChainPanel)
            or self.chain.detail.event.node_id != self.selected_node_id
        ):
            raise ValueError("Glasshouse debrief chain does not match selection")

    def select_injury(
        self, trace: CausalTrace, node_id: TraceNodeId
    ) -> GlasshouseDebrief | GlasshouseDebriefUnavailable:
        if not isinstance(trace, CausalTrace):
            raise TypeError("Glasshouse debrief selection requires a causal trace")
        if not isinstance(node_id, TraceNodeId):
            raise TypeError("Glasshouse debrief selection requires a trace node ID")
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
            return GlasshouseDebriefUnavailable(
                GlasshouseDebriefUnavailableCode.INJURY_NOT_RETAINED
            )
        panel = causal_chain_panel(trace, node_id)
        if isinstance(panel, CausalPanelUnavailable):
            return GlasshouseDebriefUnavailable(
                GlasshouseDebriefUnavailableCode.INJURY_NOT_RETAINED
            )
        return replace(self, selected_node_id=node_id, chain=panel)


type GlasshouseDebriefResult = GlasshouseDebrief | GlasshouseDebriefUnavailable


def glasshouse_debrief(trace: CausalTrace) -> GlasshouseDebriefResult:
    """Select the first retained injury and its causal explanation for debrief."""
    if not isinstance(trace, CausalTrace):
        raise TypeError("Glasshouse debrief requires a causal trace")
    injuries = tuple(
        InjuryConsequence(
            trace_record_id(record), record.tick, record.subject_entity_ids, record.summary
        )
        for record in trace.records
        if isinstance(record, ConsequenceTrace) and record.kind is TraceConsequenceKind.INJURY
    )
    if not injuries:
        return GlasshouseDebriefUnavailable(GlasshouseDebriefUnavailableCode.NO_INJURY_RETAINED)
    panel = causal_chain_panel(trace, injuries[0].node_id)
    if isinstance(panel, CausalPanelUnavailable):
        return GlasshouseDebriefUnavailable(GlasshouseDebriefUnavailableCode.INJURY_NOT_RETAINED)
    return GlasshouseDebrief(injuries, injuries[0].node_id, panel)
