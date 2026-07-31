"""Versioned immutable policy observations for the current authority kernel."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.domain.geometry import WorldPosition, distance_from_world_subunits
from kiwi.domain.ids import EntityId
from kiwi.dsl.runtime_values import IntegerValue, QuantityValue, RecordValue
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.messages import InboxObservation, inbox_runtime_value
from kiwi.sim.state import MissionState

OBSERVATION_SCHEMA_VERSION = 2
OBSERVATION_RECORD_TYPE = "Observation"
SELF_OBSERVATION_RECORD_TYPE = "SelfObservation"
POSITION_RECORD_TYPE = "Position"


@dataclass(frozen=True, slots=True)
class SelfObservation:
    """The current owner-visible entity identity and planar position."""

    entity_id: EntityId
    position: WorldPosition

    def __post_init__(self) -> None:
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("self observation requires an entity ID")
        if not isinstance(self.position, WorldPosition):
            raise ValueError("self observation requires a world position")


@dataclass(frozen=True, slots=True)
class RuntimeObservation:
    """The complete version-2 policy input with no hidden or writable state."""

    self_observation: SelfObservation
    tick: int
    inbox: InboxObservation = InboxObservation()

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


def build_runtime_observations(state: MissionState) -> tuple[RuntimeObservation, ...]:
    """Snapshot owner-visible policy inputs from one immutable pre-evaluation state."""
    if not isinstance(state, MissionState):
        raise TypeError("runtime observation building requires mission state")
    return tuple(
        RuntimeObservation(SelfObservation(entity.entity_id, entity.position), state.tick)
        for entity in state.entities
    )


def observation_runtime_value(observation: RuntimeObservation) -> RecordValue:
    """Convert one authority observation to the closed version-2 DSL record layout."""
    if not isinstance(observation, RuntimeObservation):
        raise TypeError("runtime observation value requires a RuntimeObservation")
    self_observation = observation.self_observation
    position = self_observation.position
    position_value = RecordValue(
        POSITION_RECORD_TYPE,
        ("x", "y"),
        (
            QuantityValue(distance_from_world_subunits(position.x)),
            QuantityValue(distance_from_world_subunits(position.y)),
        ),
    )
    self_value = RecordValue(
        SELF_OBSERVATION_RECORD_TYPE,
        ("entity_id", "position"),
        (IntegerValue(self_observation.entity_id.value), position_value),
    )
    return RecordValue(
        OBSERVATION_RECORD_TYPE,
        ("inbox", "self", "tick"),
        (inbox_runtime_value(observation.inbox), self_value, IntegerValue(observation.tick)),
    )
