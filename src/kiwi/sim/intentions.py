"""Closed tactical-intention kinds and their exclusive action channels."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from kiwi.domain.geometry import WorldPosition, world_subunits_from_distance
from kiwi.domain.ids import CoverId, EntityId, IntentionId, PolicyInvocationId, WeaponId
from kiwi.domain.quantities import Quantity, QuantityDimension
from kiwi.dsl.capabilities import (
    AIM_CAPABILITY,
    FIRE_CAPABILITY,
    MOVE_TOWARD_CAPABILITY,
    TAKE_COVER_CAPABILITY,
    WAIT_CAPABILITY,
    CapabilityId,
)
from kiwi.dsl.ids import ExpressionId
from kiwi.dsl.runtime_values import (
    MAX_RUNTIME_LIST_ITEMS,
    IntegerValue,
    QuantityValue,
    RecordValue,
    RuntimeValue,
    StringValue,
)
from kiwi.dsl.source import SourceSpan
from kiwi.sim.covers import CoverSide
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


class IntentionValidationCode(StrEnum):
    """Stable failures while decoding one runtime intention request."""

    EXPECTED_RECORD = "I001_EXPECTED_RECORD"
    UNSUPPORTED_KIND = "I002_UNSUPPORTED_KIND"
    INVALID_FIELDS = "I003_INVALID_FIELDS"
    INVALID_DURATION = "I004_INVALID_DURATION"
    INVALID_TARGET = "I005_INVALID_TARGET"
    INVALID_COVER_ID = "I006_INVALID_COVER_ID"
    INVALID_COVER_SIDE = "I007_INVALID_COVER_SIDE"
    INVALID_WEAPON_ID = "I008_INVALID_WEAPON_ID"


@dataclass(frozen=True, slots=True)
class IntentionValidationFailure:
    """A deterministic invalid-intention result with a local field path."""

    code: IntentionValidationCode
    message: str
    path: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.code, IntentionValidationCode):
            raise ValueError("intention validation failure requires a validation code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("intention validation failure requires a message")
        if not isinstance(self.path, tuple) or any(
            not isinstance(part, str) or not part for part in self.path
        ):
            raise ValueError("intention validation failure path must be non-empty strings")


@dataclass(frozen=True, slots=True)
class WaitIntention:
    """A positive exact wait duration that occupies the locomotion channel."""

    duration: Quantity
    kind: IntentionKind = field(default=IntentionKind.WAIT, init=False)
    action_channel: ActionChannel = field(default=ActionChannel.LOCOMOTION, init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.duration, Quantity):
            raise ValueError("wait intention requires a duration quantity")
        if self.duration.dimension is not QuantityDimension.DURATION:
            raise ValueError("wait intention requires a duration quantity")
        if self.duration.value.numerator <= 0:
            raise ValueError("wait intention duration must be positive")


@dataclass(frozen=True, slots=True)
class MoveTowardIntention:
    """A planar destination resolved on the issuer's current elevation layer."""

    target: WorldPosition
    kind: IntentionKind = field(default=IntentionKind.MOVE_TOWARD, init=False)
    action_channel: ActionChannel = field(default=ActionChannel.LOCOMOTION, init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.target, WorldPosition):
            raise ValueError("move-toward intention requires a world position")
        if self.target.elevation.value != 0:
            raise ValueError("move-toward intention target must be planar")


@dataclass(frozen=True, slots=True)
class TakeCoverIntention:
    """A request for the canonical first eligible slot on one cover side."""

    cover_id: CoverId
    side: CoverSide
    kind: IntentionKind = field(default=IntentionKind.TAKE_COVER, init=False)
    action_channel: ActionChannel = field(default=ActionChannel.LOCOMOTION, init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.cover_id, CoverId):
            raise ValueError("take-cover intention requires a cover ID")
        if not isinstance(self.side, CoverSide):
            raise ValueError("take-cover intention requires a cover side")


@dataclass(frozen=True, slots=True)
class AimIntention:
    """A target-free weapon-channel action that retains automatic aim progression."""

    kind: IntentionKind = field(default=IntentionKind.AIM, init=False)
    action_channel: ActionChannel = field(default=ActionChannel.WEAPON, init=False)


@dataclass(frozen=True, slots=True)
class FireIntention:
    """One exact planar weapon request against a policy-visible target position."""

    weapon_id: WeaponId
    target: WorldPosition
    kind: IntentionKind = field(default=IntentionKind.FIRE, init=False)
    action_channel: ActionChannel = field(default=ActionChannel.WEAPON, init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.weapon_id, WeaponId):
            raise ValueError("fire intention requires a weapon ID")
        if not isinstance(self.target, WorldPosition):
            raise ValueError("fire intention requires a world position")
        if self.target.elevation.value != 0:
            raise ValueError("fire intention target must be planar")


type ValidatedIntention = (
    AimIntention | FireIntention | MoveTowardIntention | TakeCoverIntention | WaitIntention
)
type IntentionValidationResult = ValidatedIntention | IntentionValidationFailure


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


def validate_runtime_intention(value: RuntimeValue) -> IntentionValidationResult:
    """Decode one closed runtime request into an available authority intention."""
    if not isinstance(value, RecordValue):
        return IntentionValidationFailure(
            IntentionValidationCode.EXPECTED_RECORD,
            "intention must be a record value",
        )
    if value.type_name == "MoveToward":
        return _validate_move_toward(value)
    if value.type_name == "TakeCover":
        return _validate_take_cover(value)
    if value.type_name == "Aim":
        return _validate_aim(value)
    if value.type_name == "Fire":
        return _validate_fire(value)
    if value.type_name != "Wait":
        return IntentionValidationFailure(
            IntentionValidationCode.UNSUPPORTED_KIND,
            f"intention kind '{value.type_name}' is unavailable",
        )
    if value.field_names != ("duration",):
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_FIELDS,
            "Wait intention must contain exactly a duration field",
        )
    duration = value.field_value("duration")
    if (
        not isinstance(duration, QuantityValue)
        or duration.value.dimension is not QuantityDimension.DURATION
    ):
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_DURATION,
            "Wait.duration must be a Duration value",
            ("duration",),
        )
    if duration.value.value.numerator <= 0:
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_DURATION,
            "Wait.duration must be positive",
            ("duration",),
        )
    return WaitIntention(duration.value)


def _validate_move_toward(value: RecordValue) -> IntentionValidationResult:
    if value.field_names != ("target",):
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_FIELDS,
            "MoveToward intention must contain exactly a target field",
        )
    target = value.field_value("target")
    if not isinstance(target, RecordValue) or target.type_name != "Position":
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_TARGET,
            "MoveToward.target must be a Position value",
            ("target",),
        )
    if target.field_names != ("x", "y"):
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_TARGET,
            "MoveToward.target must contain exactly x and y fields",
            ("target",),
        )
    x, y = target.values
    if (
        not isinstance(x, QuantityValue)
        or x.value.dimension is not QuantityDimension.DISTANCE
        or not isinstance(y, QuantityValue)
        or y.value.dimension is not QuantityDimension.DISTANCE
    ):
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_TARGET,
            "MoveToward.target coordinates must be Distance values",
            ("target",),
        )
    try:
        target_position = WorldPosition(
            world_subunits_from_distance(x.value), world_subunits_from_distance(y.value)
        )
    except ValueError:
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_TARGET,
            "MoveToward.target coordinates are outside canonical world bounds",
            ("target",),
        )
    return MoveTowardIntention(target_position)


def _validate_take_cover(value: RecordValue) -> IntentionValidationResult:
    if value.field_names != ("cover_id", "side"):
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_FIELDS,
            "TakeCover intention must contain exactly cover_id and side fields",
        )
    cover_id = value.field_value("cover_id")
    if not isinstance(cover_id, IntegerValue):
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_COVER_ID,
            "TakeCover.cover_id must be a positive cover ID",
            ("cover_id",),
        )
    try:
        resolved_cover_id = CoverId(cover_id.value)
    except ValueError:
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_COVER_ID,
            "TakeCover.cover_id must be a positive cover ID",
            ("cover_id",),
        )
    side = value.field_value("side")
    if not isinstance(side, StringValue):
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_COVER_SIDE,
            "TakeCover.side must be left or right",
            ("side",),
        )
    try:
        resolved_side = CoverSide(side.value)
    except ValueError:
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_COVER_SIDE,
            "TakeCover.side must be left or right",
            ("side",),
        )
    return TakeCoverIntention(resolved_cover_id, resolved_side)


def _validate_aim(value: RecordValue) -> IntentionValidationResult:
    if value.field_names != ():
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_FIELDS,
            "Aim intention must not contain fields",
        )
    return AimIntention()


def _validate_fire(value: RecordValue) -> IntentionValidationResult:
    if value.field_names != ("target", "weapon_id"):
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_FIELDS,
            "Fire intention must contain exactly target and weapon_id fields",
        )
    weapon_id = value.field_value("weapon_id")
    if not isinstance(weapon_id, IntegerValue):
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_WEAPON_ID,
            "Fire.weapon_id must be a positive weapon ID",
            ("weapon_id",),
        )
    try:
        resolved_weapon_id = WeaponId(weapon_id.value)
    except ValueError:
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_WEAPON_ID,
            "Fire.weapon_id must be a positive weapon ID",
            ("weapon_id",),
        )
    target = _target_position(value.field_value("target"), "Fire")
    if isinstance(target, IntentionValidationFailure):
        return target
    return FireIntention(resolved_weapon_id, target)


def _target_position(
    value: RuntimeValue | None, intention_name: str
) -> WorldPosition | IntentionValidationFailure:
    if not isinstance(value, RecordValue) or value.type_name != "Position":
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_TARGET,
            f"{intention_name}.target must be a Position value",
            ("target",),
        )
    if value.field_names != ("x", "y"):
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_TARGET,
            f"{intention_name}.target must contain exactly x and y fields",
            ("target",),
        )
    x, y = value.values
    if (
        not isinstance(x, QuantityValue)
        or x.value.dimension is not QuantityDimension.DISTANCE
        or not isinstance(y, QuantityValue)
        or y.value.dimension is not QuantityDimension.DISTANCE
    ):
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_TARGET,
            f"{intention_name}.target coordinates must be Distance values",
            ("target",),
        )
    try:
        return WorldPosition(
            world_subunits_from_distance(x.value), world_subunits_from_distance(y.value)
        )
    except ValueError:
        return IntentionValidationFailure(
            IntentionValidationCode.INVALID_TARGET,
            f"{intention_name}.target coordinates are outside canonical world bounds",
            ("target",),
        )


def required_capability_for(intention: ValidatedIntention) -> CapabilityId:
    """Return the declared tactical capability required by an available intention."""
    if isinstance(intention, AimIntention):
        return AIM_CAPABILITY
    if isinstance(intention, FireIntention):
        return FIRE_CAPABILITY
    if isinstance(intention, MoveTowardIntention):
        return MOVE_TOWARD_CAPABILITY
    if isinstance(intention, TakeCoverIntention):
        return TAKE_COVER_CAPABILITY
    if isinstance(intention, WaitIntention):
        return WAIT_CAPABILITY
    raise TypeError("intention capability lookup requires a validated intention")
