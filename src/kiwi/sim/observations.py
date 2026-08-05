"""Versioned immutable policy observations for the current authority kernel."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.domain.geometry import WorldPosition, WorldSubunits, distance_from_world_subunits
from kiwi.domain.ids import EntityId
from kiwi.dsl.runtime_values import (
    BooleanValue,
    IntegerValue,
    ListValue,
    OptionNoneValue,
    OptionSomeValue,
    QuantityValue,
    RecordValue,
    StringValue,
)
from kiwi.sim.conditions import MAX_OPERATIVE_HEALTH, MAX_OPERATIVE_PROTECTION, InjurySeverity
from kiwi.sim.contacts import ContactEstimate, nearest_contact_for
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.messages import InboxObservation, inbox_for, inbox_runtime_value
from kiwi.sim.signals import SignalObservation, signals_for, signals_runtime_value
from kiwi.sim.state import MissionState
from kiwi.sim.visibility import SensorRange, VisibleCover, visible_covers
from kiwi.sim.weapons import MAX_AIM_QUALITY_BASIS_POINTS

OBSERVATION_SCHEMA_VERSION = 7
OBSERVATION_RECORD_TYPE = "Observation"
SELF_OBSERVATION_RECORD_TYPE = "SelfObservation"
POSITION_RECORD_TYPE = "Position"
CONTACT_RECORD_TYPE = "Contact"
COVER_RECORD_TYPE = "Cover"
COVER_SLOT_RECORD_TYPE = "CoverSlot"
DEFAULT_OBSERVATION_SENSOR_RANGE = SensorRange(WorldSubunits(10_000))


@dataclass(frozen=True, slots=True)
class SelfObservation:
    """The current owner-visible position and exact readiness values."""

    entity_id: EntityId
    position: WorldPosition
    aim_quality_basis_points: int = 0
    aim_ceiling_basis_points: int = MAX_AIM_QUALITY_BASIS_POINTS
    suppression_basis_points: int = 0
    health: int = MAX_OPERATIVE_HEALTH
    protection: int = MAX_OPERATIVE_PROTECTION
    injury_severity: InjurySeverity = InjurySeverity.NONE
    incapacitated: bool = False
    stabilized: bool = False

    def __post_init__(self) -> None:
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("self observation requires an entity ID")
        if not isinstance(self.position, WorldPosition):
            raise ValueError("self observation requires a world position")
        values = (
            self.aim_quality_basis_points,
            self.aim_ceiling_basis_points,
            self.suppression_basis_points,
            self.health,
            self.protection,
        )
        if any(not isinstance(value, int) or isinstance(value, bool) for value in values):
            raise ValueError("self observation readiness values must be integers")
        if not 0 <= self.aim_quality_basis_points <= MAX_AIM_QUALITY_BASIS_POINTS:
            raise ValueError("self observation aim quality is outside the configured range")
        if not 0 <= self.suppression_basis_points <= MAX_AIM_QUALITY_BASIS_POINTS:
            raise ValueError("self observation suppression is outside the configured range")
        if self.aim_ceiling_basis_points != (
            MAX_AIM_QUALITY_BASIS_POINTS - self.suppression_basis_points
        ):
            raise ValueError("self observation aim ceiling must match suppression")
        if not 0 <= self.health <= MAX_OPERATIVE_HEALTH:
            raise ValueError("self observation health is outside the configured range")
        if not 0 <= self.protection <= MAX_OPERATIVE_PROTECTION:
            raise ValueError("self observation protection is outside the configured range")
        if not isinstance(self.injury_severity, InjurySeverity):
            raise ValueError("self observation injury severity must be an injury severity")
        if not isinstance(self.incapacitated, bool):
            raise ValueError("self observation incapacitation state must be boolean")
        if not isinstance(self.stabilized, bool):
            raise ValueError("self observation stabilization state must be boolean")
        if self.injury_severity is not _injury_severity_for_health(self.health):
            raise ValueError("self observation injury severity must match health")
        if self.incapacitated != (self.health == 0):
            raise ValueError("self observation incapacitation state must match health")


@dataclass(frozen=True, slots=True)
class RuntimeObservation:
    """The complete version-7 policy input with no hidden or writable state."""

    self_observation: SelfObservation
    tick: int
    inbox: InboxObservation = InboxObservation()
    signals: tuple[SignalObservation, ...] = ()
    nearest_contact: ContactEstimate | None = None
    visible_covers: tuple[VisibleCover, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.self_observation, SelfObservation):
            raise ValueError("runtime observation requires self observation")
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("runtime observation tick must be an integer")
        if not 0 <= self.tick <= MAX_AUTHORITY_TICK:
            raise ValueError("runtime observation tick must fit non-negative signed 64-bit range")
        if not isinstance(self.inbox, InboxObservation):
            raise ValueError("runtime observation requires an inbox observation")
        if any(
            message.recipient_entity_id != self.self_observation.entity_id
            for message in self.inbox.messages
        ):
            raise ValueError("runtime observation inbox messages must belong to its entity")
        if any(
            message.delivery_tick > self.tick or message.expiry_tick < self.tick
            for message in self.inbox.messages
        ):
            raise ValueError("runtime observation inbox messages must be delivered and unexpired")
        if not isinstance(self.signals, tuple):
            raise ValueError("runtime observation signals must be an immutable tuple")
        previous_sequence = -1
        for signal in self.signals:
            if not isinstance(signal, SignalObservation):
                raise ValueError("runtime observation signals must contain signal observations")
            if signal.tick != self.tick:
                raise ValueError("runtime observation signals must match the observation tick")
            if signal.target_entity_id not in (None, self.self_observation.entity_id):
                raise ValueError("runtime observation signals must belong to its entity")
            if signal.command_sequence <= previous_sequence:
                raise ValueError("runtime observation signals must be command-sequence ordered")
            previous_sequence = signal.command_sequence
        if self.nearest_contact is not None:
            if not isinstance(self.nearest_contact, ContactEstimate):
                raise ValueError("runtime observation nearest contact must be a contact estimate")
            if self.nearest_contact.owner_entity_id != self.self_observation.entity_id:
                raise ValueError("runtime observation nearest contact must belong to its entity")
            self.nearest_contact.age_at(self.tick)
        if not isinstance(self.visible_covers, tuple):
            raise ValueError("runtime observation visible covers must be an immutable tuple")
        previous_cover_id = 0
        for cover in self.visible_covers:
            if not isinstance(cover, VisibleCover):
                raise ValueError("runtime observation visible covers must contain visible covers")
            if cover.cover_id.value <= previous_cover_id:
                raise ValueError("runtime observation visible covers must be cover-ID ordered")
            if cover.segment.start.elevation != self.self_observation.position.elevation:
                raise ValueError(
                    "runtime observation visible covers must share its entity elevation"
                )
            previous_cover_id = cover.cover_id.value


def build_runtime_observations(state: MissionState) -> tuple[RuntimeObservation, ...]:
    """Snapshot owner-visible policy inputs from one immutable pre-evaluation state."""
    if not isinstance(state, MissionState):
        raise TypeError("runtime observation building requires mission state")
    return tuple(
        _runtime_observation_for(state, entity.entity_id, entity.position)
        for entity in state.entities
    )


def _runtime_observation_for(
    state: MissionState,
    entity_id: EntityId,
    position: WorldPosition,
) -> RuntimeObservation:
    condition = state.conditions.condition_for(entity_id)
    suppression = state.suppressions.suppression_for(entity_id)
    return RuntimeObservation(
        SelfObservation(
            entity_id,
            position,
            state.aim_states.quality_for(entity_id),
            MAX_AIM_QUALITY_BASIS_POINTS - suppression,
            suppression,
            condition.health,
            condition.protection,
            condition.injury_severity,
            condition.incapacitated,
            condition.stabilized,
        ),
        state.tick,
        inbox_for(state.messages, entity_id, state.tick),
        signals_for(state.signals, entity_id, state.tick),
        nearest_contact_for(state.contacts, entity_id, position, state.tick),
        visible_covers(state.covers, position, DEFAULT_OBSERVATION_SENSOR_RANGE),
    )


def observation_runtime_value(observation: RuntimeObservation) -> RecordValue:
    """Convert one authority observation to the closed version-7 DSL record layout."""
    if not isinstance(observation, RuntimeObservation):
        raise TypeError("runtime observation value requires a RuntimeObservation")
    self_observation = observation.self_observation
    position_value = _position_runtime_value(self_observation.position)
    self_value = RecordValue(
        SELF_OBSERVATION_RECORD_TYPE,
        (
            "aim_ceiling_basis_points",
            "aim_quality_basis_points",
            "entity_id",
            "health",
            "incapacitated",
            "injury_severity",
            "position",
            "protection",
            "stabilized",
            "suppression_basis_points",
        ),
        (
            IntegerValue(self_observation.aim_ceiling_basis_points),
            IntegerValue(self_observation.aim_quality_basis_points),
            IntegerValue(self_observation.entity_id.value),
            IntegerValue(self_observation.health),
            BooleanValue(self_observation.incapacitated),
            StringValue(self_observation.injury_severity.value),
            position_value,
            IntegerValue(self_observation.protection),
            BooleanValue(self_observation.stabilized),
            IntegerValue(self_observation.suppression_basis_points),
        ),
    )
    return RecordValue(
        OBSERVATION_RECORD_TYPE,
        ("inbox", "nearest_contact", "self", "signals", "tick", "visible_covers"),
        (
            inbox_runtime_value(observation.inbox),
            _nearest_contact_runtime_value(observation.nearest_contact, observation.tick),
            self_value,
            signals_runtime_value(observation.signals),
            IntegerValue(observation.tick),
            ListValue(
                tuple(_visible_cover_runtime_value(cover) for cover in observation.visible_covers)
            ),
        ),
    )


def _nearest_contact_runtime_value(
    contact: ContactEstimate | None, current_tick: int
) -> OptionNoneValue | OptionSomeValue:
    if contact is None:
        return OptionNoneValue()
    return OptionSomeValue(
        RecordValue(
            CONTACT_RECORD_TYPE,
            (
                "age_ticks",
                "confidence_basis_points",
                "contact_id",
                "estimated_position",
                "uncertainty_radius",
            ),
            (
                IntegerValue(contact.age_at(current_tick).ticks),
                IntegerValue(contact.confidence.basis_points),
                IntegerValue(contact.contact_id.value),
                _position_runtime_value(contact.estimated_position),
                QuantityValue(distance_from_world_subunits(contact.uncertainty_radius)),
            ),
        )
    )


def _injury_severity_for_health(health: int) -> InjurySeverity:
    if health == MAX_OPERATIVE_HEALTH:
        return InjurySeverity.NONE
    if health == MAX_OPERATIVE_HEALTH - 1:
        return InjurySeverity.MINOR
    if health == 1:
        return InjurySeverity.SEVERE
    return InjurySeverity.INCAPACITATED


def _position_runtime_value(position: WorldPosition) -> RecordValue:
    return RecordValue(
        POSITION_RECORD_TYPE,
        ("x", "y"),
        (
            QuantityValue(distance_from_world_subunits(position.x)),
            QuantityValue(distance_from_world_subunits(position.y)),
        ),
    )


def _visible_cover_runtime_value(cover: VisibleCover) -> RecordValue:
    segment = cover.segment
    return RecordValue(
        COVER_RECORD_TYPE,
        ("cover_id", "end", "height", "integrity_basis_points", "slots", "start"),
        (
            IntegerValue(segment.cover_id.value),
            _position_runtime_value(segment.end),
            StringValue(segment.height.value),
            IntegerValue(segment.integrity.basis_points),
            ListValue(
                tuple(
                    RecordValue(
                        COVER_SLOT_RECORD_TYPE,
                        ("position", "side", "slot_index"),
                        (
                            _position_runtime_value(slot.position),
                            StringValue(slot.side.value),
                            IntegerValue(slot.slot_index),
                        ),
                    )
                    for slot in segment.slots
                )
            ),
            _position_runtime_value(segment.start),
        ),
    )
