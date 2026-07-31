"""Versioned immutable policy observations for the current authority kernel."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.domain.geometry import WorldPosition, distance_from_world_subunits
from kiwi.domain.ids import EntityId
from kiwi.dsl.runtime_values import IntegerValue, QuantityValue, RecordValue
from kiwi.sim.limits import MAX_AUTHORITY_TICK

OBSERVATION_SCHEMA_VERSION = 1
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
    """The complete version-1 policy input with no hidden or writable state."""

    self_observation: SelfObservation
    tick: int

    def __post_init__(self) -> None:
        if not isinstance(self.self_observation, SelfObservation):
            raise ValueError("runtime observation requires self observation")
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("runtime observation tick must be an integer")
        if not 0 <= self.tick <= MAX_AUTHORITY_TICK:
            raise ValueError("runtime observation tick must fit non-negative signed 64-bit range")


def observation_runtime_value(observation: RuntimeObservation) -> RecordValue:
    """Convert one authority observation to the closed version-1 DSL record layout."""
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
        ("self", "tick"),
        (self_value, IntegerValue(observation.tick)),
    )
