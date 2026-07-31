from __future__ import annotations

import pytest

from kiwi.sim.intentions import (
    CORE_INTENTION_KINDS,
    ActionChannel,
    IntentionKind,
    action_channel_for,
)


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
