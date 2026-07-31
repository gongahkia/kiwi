"""Closed tactical-intention kinds and their exclusive action channels."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from kiwi.domain.ids import EntityId, IntentionId, PolicyInvocationId
from kiwi.dsl.ids import ExpressionId
from kiwi.dsl.runtime_values import MAX_RUNTIME_LIST_ITEMS
from kiwi.dsl.source import SourceSpan
from kiwi.sim.limits import MAX_AUTHORITY_TICK

MAX_POLICY_INTENTIONS = MAX_RUNTIME_LIST_ITEMS


class ActionChannel(StrEnum):
    """One independently arbitrated action capacity for an entity."""

    LOCOMOTION = "locomotion"
    WEAPON = "weapon"
    INTERACTION = "interaction"
    MEDICAL = "medical"
    COMMUNICATION = "communication"


class IntentionKind(StrEnum):
    """The closed core tactical requests that policies may eventually emit."""

    MOVE_TOWARD = "move_toward"
    TAKE_COVER = "take_cover"
    AIM = "aim"
    FIRE = "fire"
    STABILISE = "stabilise"
    USE = "use"
    EMIT = "emit"
    WAIT = "wait"


CORE_INTENTION_KINDS = tuple(IntentionKind)


@dataclass(frozen=True, slots=True)
class IntentionOrigin:
    """Immutable causal provenance assigned to one policy-emitted intention."""

    intention_id: IntentionId
    issuer_entity_id: EntityId
    invocation_id: PolicyInvocationId
    source_expression_id: ExpressionId
    source_span: SourceSpan
    policy_order: int
    creation_tick: int
    kind: IntentionKind
    action_channel: ActionChannel = field(init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.intention_id, IntentionId):
            raise ValueError("intention origin requires an intention ID")
        if not isinstance(self.issuer_entity_id, EntityId):
            raise ValueError("intention origin requires an issuer entity ID")
        if not isinstance(self.invocation_id, PolicyInvocationId):
            raise ValueError("intention origin requires a policy invocation ID")
        if not isinstance(self.source_expression_id, ExpressionId):
            raise ValueError("intention origin requires a source expression ID")
        if not isinstance(self.source_span, SourceSpan):
            raise ValueError("intention origin requires a source span")
        if (
            not isinstance(self.policy_order, int)
            or isinstance(self.policy_order, bool)
            or not 0 <= self.policy_order < MAX_POLICY_INTENTIONS
        ):
            raise ValueError("intention origin policy order is outside the configured list limit")
        if (
            not isinstance(self.creation_tick, int)
            or isinstance(self.creation_tick, bool)
            or not 0 <= self.creation_tick <= MAX_AUTHORITY_TICK
        ):
            raise ValueError(
                "intention origin creation tick must fit non-negative signed 64-bit range"
            )
        if not isinstance(self.kind, IntentionKind):
            raise ValueError("intention origin requires an intention kind")
        object.__setattr__(self, "action_channel", action_channel_for(self.kind))


def action_channel_for(kind: IntentionKind) -> ActionChannel:
    """Return the one exclusive channel arbitrating a core intention kind."""
    if not isinstance(kind, IntentionKind):
        raise ValueError("action channel lookup requires an intention kind")
    if kind in (
        IntentionKind.MOVE_TOWARD,
        IntentionKind.TAKE_COVER,
        IntentionKind.WAIT,
    ):
        return ActionChannel.LOCOMOTION
    if kind in (IntentionKind.AIM, IntentionKind.FIRE):
        return ActionChannel.WEAPON
    if kind is IntentionKind.STABILISE:
        return ActionChannel.MEDICAL
    if kind is IntentionKind.USE:
        return ActionChannel.INTERACTION
    if kind is IntentionKind.EMIT:
        return ActionChannel.COMMUNICATION
    raise AssertionError("core intention kind is not assigned an action channel")
