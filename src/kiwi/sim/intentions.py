"""Closed tactical-intention kinds and their exclusive action channels."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from kiwi.domain.ids import EntityId, IntentionId, PolicyInvocationId
from kiwi.domain.quantities import Quantity, QuantityDimension
from kiwi.dsl.capabilities import WAIT_CAPABILITY, CapabilityId
from kiwi.dsl.ids import ExpressionId
from kiwi.dsl.runtime_values import MAX_RUNTIME_LIST_ITEMS, QuantityValue, RecordValue, RuntimeValue
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


class IntentionValidationCode(StrEnum):
    """Stable failures while decoding one runtime intention request."""

    EXPECTED_RECORD = "I001_EXPECTED_RECORD"
    UNSUPPORTED_KIND = "I002_UNSUPPORTED_KIND"
    INVALID_FIELDS = "I003_INVALID_FIELDS"
    INVALID_DURATION = "I004_INVALID_DURATION"


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


type ValidatedIntention = WaitIntention
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


def required_capability_for(intention: ValidatedIntention) -> CapabilityId:
    """Return the declared tactical capability required by an available intention."""
    if isinstance(intention, WaitIntention):
        return WAIT_CAPABILITY
    raise TypeError("intention capability lookup requires a validated intention")
