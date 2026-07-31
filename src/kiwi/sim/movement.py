"""Canonical fixed-step progression of active movement actions."""

from __future__ import annotations

from dataclasses import replace

from kiwi.domain.geometry import WorldPosition
from kiwi.sim.state import (
    MissionState,
    MovementAction,
    movement_action_position,
    movement_action_segment_length,
)

OPERATIVE_MOVE_SPEED_PER_TICK = 100


def progress_movement_actions(state: MissionState) -> MissionState:
    """Advance every active action once in canonical entity-ID order."""
    if not isinstance(state, MissionState):
        raise ValueError("movement progression requires mission state")
    if not state.movement_actions:
        return state
    advances = tuple(
        (action.entity_id.value, *_advance_action(action)) for action in state.movement_actions
    )
    entities = tuple(
        replace(
            entity, position=_position_for_entity(entity.entity_id.value, advances, entity.position)
        )
        for entity in state.entities
    )
    actions = tuple(action for _, action, _ in advances if action is not None)
    return replace(state, entities=entities, movement_actions=actions)


def _advance_action(action: MovementAction) -> tuple[MovementAction | None, WorldPosition]:
    length = movement_action_segment_length(action)
    progressed = min(action.segment_progress + OPERATIVE_MOVE_SPEED_PER_TICK, length)
    if progressed < length:
        successor = replace(action, segment_progress=progressed)
        return successor, movement_action_position(successor)
    target = action.path.waypoints[action.next_waypoint_index]
    if action.next_waypoint_index + 1 == len(action.path.waypoints):
        return None, target
    return replace(
        action, next_waypoint_index=action.next_waypoint_index + 1, segment_progress=0
    ), target


def _position_for_entity(
    entity_id: int,
    advances: tuple[tuple[int, MovementAction | None, WorldPosition], ...],
    current: WorldPosition,
) -> WorldPosition:
    for action_entity_id, _, position in advances:
        if action_entity_id == entity_id:
            return position
    return current
