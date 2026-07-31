from __future__ import annotations

import pytest

from kiwi.domain.ids import EntityId, IntentionId, PolicyInvocationId
from kiwi.dsl.ids import ExpressionId
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.sim.intentions import (
    CORE_INTENTION_KINDS,
    ActionChannel,
    IntentionKind,
    IntentionOrigin,
    action_channel_for,
)
from kiwi.sim.limits import MAX_AUTHORITY_TICK


def test_core_intention_kinds_have_explicit_stable_action_channels() -> None:
    assert CORE_INTENTION_KINDS == (
        IntentionKind.MOVE_TOWARD,
        IntentionKind.TAKE_COVER,
        IntentionKind.AIM,
        IntentionKind.FIRE,
        IntentionKind.STABILISE,
        IntentionKind.USE,
        IntentionKind.EMIT,
        IntentionKind.WAIT,
    )
    assert tuple(action_channel_for(kind) for kind in CORE_INTENTION_KINDS) == (
        ActionChannel.LOCOMOTION,
        ActionChannel.LOCOMOTION,
        ActionChannel.WEAPON,
        ActionChannel.WEAPON,
        ActionChannel.MEDICAL,
        ActionChannel.INTERACTION,
        ActionChannel.COMMUNICATION,
        ActionChannel.LOCOMOTION,
    )


def test_action_channel_lookup_rejects_non_intention_kinds() -> None:
    with pytest.raises(ValueError, match="intention kind"):
        action_channel_for("wait")  # type: ignore[arg-type]


def test_intention_origin_retains_typed_causal_metadata() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "Wait(1s)")

    origin = IntentionOrigin(
        IntentionId(7),
        EntityId(3),
        PolicyInvocationId(2),
        ExpressionId(11),
        source.span(ByteOffset(0), ByteOffset(8)),
        0,
        19,
        IntentionKind.WAIT,
    )

    assert origin.intention_id == IntentionId(7)
    assert origin.issuer_entity_id == EntityId(3)
    assert origin.invocation_id == PolicyInvocationId(2)
    assert origin.source_expression_id == ExpressionId(11)
    assert origin.source_span == source.span(ByteOffset(0), ByteOffset(8))
    assert origin.policy_order == 0
    assert origin.creation_tick == 19
    assert origin.action_channel is ActionChannel.LOCOMOTION


@pytest.mark.parametrize(
    ("arguments", "message"),
    (
        ((object(), EntityId(1), PolicyInvocationId(1), ExpressionId(1), 0, 0), "intention ID"),
        ((IntentionId(1), object(), PolicyInvocationId(1), ExpressionId(1), 0, 0), "issuer"),
        ((IntentionId(1), EntityId(1), object(), ExpressionId(1), 0, 0), "invocation"),
        ((IntentionId(1), EntityId(1), PolicyInvocationId(1), object(), 0, 0), "expression"),
        (
            (IntentionId(1), EntityId(1), PolicyInvocationId(1), ExpressionId(1), -1, 0),
            "policy order",
        ),
        (
            (
                IntentionId(1),
                EntityId(1),
                PolicyInvocationId(1),
                ExpressionId(1),
                0,
                MAX_AUTHORITY_TICK + 1,
            ),
            "creation tick",
        ),
    ),
)
def test_intention_origin_rejects_invalid_provenance(
    arguments: tuple[object, object, object, object, int, int], message: str
) -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "Wait(1s)")
    intention_id, issuer, invocation, expression, policy_order, creation_tick = arguments

    with pytest.raises(ValueError, match=message):
        IntentionOrigin(
            intention_id,  # type: ignore[arg-type]
            issuer,  # type: ignore[arg-type]
            invocation,  # type: ignore[arg-type]
            expression,  # type: ignore[arg-type]
            source.span(ByteOffset(0), ByteOffset(8)),
            policy_order,
            creation_tick,
            IntentionKind.WAIT,
        )
