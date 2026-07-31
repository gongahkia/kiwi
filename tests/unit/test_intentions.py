from __future__ import annotations

import pytest

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldSubunits
from kiwi.domain.ids import EntityId, IntentionId, PolicyInvocationId
from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.dsl.ids import ExpressionId
from kiwi.dsl.runtime_values import IntegerValue, QuantityValue, RecordValue
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.sim.intentions import (
    CORE_INTENTION_KINDS,
    ActionChannel,
    IntentionKind,
    IntentionOrigin,
    IntentionValidationCode,
    IntentionValidationFailure,
    MoveTowardIntention,
    WaitIntention,
    action_channel_for,
    validate_runtime_intention,
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


def test_runtime_intention_validation_accepts_well_formed_available_intentions() -> None:
    duration = Quantity(QuantityDimension.DURATION, ExactRational(1, 2))
    distance_x = Quantity(QuantityDimension.DISTANCE, ExactRational(3, 2))
    distance_y = Quantity(QuantityDimension.DISTANCE, ExactRational(-1, 2))

    validated = validate_runtime_intention(
        RecordValue("Wait", ("duration",), (QuantityValue(duration),))
    )
    move = validate_runtime_intention(
        RecordValue(
            "MoveToward",
            ("target",),
            (
                RecordValue(
                    "Position",
                    ("x", "y"),
                    (QuantityValue(distance_x), QuantityValue(distance_y)),
                ),
            ),
        )
    )
    malformed = validate_runtime_intention(RecordValue("Wait", ("duration",), (IntegerValue(1),)))
    malformed_target = validate_runtime_intention(
        RecordValue("MoveToward", ("target",), (IntegerValue(1),))
    )
    unavailable = validate_runtime_intention(RecordValue("Fire", (), ()))

    assert validated == WaitIntention(duration)
    assert move == MoveTowardIntention(WorldPosition(WorldSubunits(1_500), WorldSubunits(-500)))
    assert malformed == IntentionValidationFailure(
        IntentionValidationCode.INVALID_DURATION,
        "Wait.duration must be a Duration value",
        ("duration",),
    )
    assert unavailable == IntentionValidationFailure(
        IntentionValidationCode.UNSUPPORTED_KIND,
        "intention kind 'Fire' is unavailable",
    )
    assert malformed_target == IntentionValidationFailure(
        IntentionValidationCode.INVALID_TARGET,
        "MoveToward.target must be a Position value",
        ("target",),
    )


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


def test_move_toward_intention_rejects_a_nonplanar_target() -> None:
    with pytest.raises(ValueError, match="planar"):
        MoveTowardIntention(WorldPosition(WorldSubunits(0), WorldSubunits(0), ElevationLayer(1)))


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
