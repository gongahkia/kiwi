"""Closed tactical-intention kinds and their exclusive action channels."""

from __future__ import annotations

from enum import StrEnum


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
