"""Repeatable headless-run verification and canonical state differences."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.domain.ids import IdKind
from kiwi.sim.clock import FixedTickClock
from kiwi.sim.commands import ExternalCommand
from kiwi.sim.hashing import StateHash, encode_canonical_state, hash_canonical_state
from kiwi.sim.policies import EMPTY_POLICY_BINDINGS, PolicyBindings
from kiwi.sim.randomness import RandomStreamId
from kiwi.sim.runner import HeadlessRun, run_headless
from kiwi.sim.snapshot import AuthoritySnapshot, restore_authority_snapshot
from kiwi.sim.state import MissionState


@dataclass(frozen=True, slots=True)
class CanonicalStateDifference:
    """The first canonical field with distinct expected and actual values."""

    path: str
    expected: str
    actual: str


@dataclass(frozen=True, slots=True)
class DeterminismDivergence:
    """One earliest differing checkpoint with its hashes and state difference."""

    tick: int
    expected_hash: StateHash
    actual_hash: StateHash
    difference: CanonicalStateDifference


@dataclass(frozen=True, slots=True)
class DeterminismReport:
    """Two reruns and their first known divergence, if any."""

    expected: HeadlessRun
    actual: HeadlessRun
    divergence: DeterminismDivergence | None

    @property
    def matches(self) -> bool:
        """Return whether identical inputs produced identical checkpoint hashes."""
        return self.divergence is None


def run_determinism_harness(
    state: MissionState,
    clock: FixedTickClock,
    ticks: int,
    commands: tuple[ExternalCommand, ...] = (),
    checkpoint_interval: int = 1,
    policy_bindings: PolicyBindings = EMPTY_POLICY_BINDINGS,
) -> DeterminismReport:
    """Run the same immutable inputs twice and compare all checkpoint hashes."""
    if not isinstance(policy_bindings, PolicyBindings):
        raise ValueError("determinism harness policy bindings must be policy bindings")
    expected = run_headless(state, clock, ticks, commands, checkpoint_interval, policy_bindings)
    actual = run_headless(state, clock, ticks, commands, checkpoint_interval, policy_bindings)
    return DeterminismReport(expected, actual, compare_headless_runs(expected, actual))


def compare_headless_runs(
    expected: HeadlessRun, actual: HeadlessRun
) -> DeterminismDivergence | None:
    """Return the earliest checkpoint or final-state divergence between two runs."""
    if not isinstance(expected, HeadlessRun) or not isinstance(actual, HeadlessRun):
        raise TypeError("determinism comparison requires headless runs")
    if len(expected.checkpoints) != len(actual.checkpoints):
        return _divergence(
            min(expected.state.tick, actual.state.tick),
            hash_canonical_state(expected.state),
            hash_canonical_state(actual.state),
            CanonicalStateDifference(
                "checkpoints/count",
                str(len(expected.checkpoints)),
                str(len(actual.checkpoints)),
            ),
        )
    for index, (expected_checkpoint, actual_checkpoint) in enumerate(
        zip(expected.checkpoints, actual.checkpoints, strict=True)
    ):
        if expected_checkpoint.tick != actual_checkpoint.tick:
            return _divergence(
                min(expected_checkpoint.tick, actual_checkpoint.tick),
                expected_checkpoint.state_hash,
                actual_checkpoint.state_hash,
                CanonicalStateDifference(
                    f"checkpoints/{index}/tick",
                    str(expected_checkpoint.tick),
                    str(actual_checkpoint.tick),
                ),
            )
        if expected_checkpoint.state_hash != actual_checkpoint.state_hash:
            return _divergence_from_checkpoints(expected_checkpoint, actual_checkpoint)
    expected_hash = hash_canonical_state(expected.state)
    actual_hash = hash_canonical_state(actual.state)
    if expected_hash != actual_hash:
        difference = first_canonical_state_difference(expected.state, actual.state)
        if difference is None:
            raise AssertionError("distinct canonical hashes require a state difference")
        return _divergence(
            max(expected.state.tick, actual.state.tick), expected_hash, actual_hash, difference
        )
    return None


def first_canonical_state_difference(
    expected: MissionState, actual: MissionState
) -> CanonicalStateDifference | None:
    """Find the first differing field in canonical-state encoding order."""
    if not isinstance(expected, MissionState) or not isinstance(actual, MissionState):
        raise TypeError("canonical state comparison requires mission states")
    expected_bytes = encode_canonical_state(expected)
    actual_bytes = encode_canonical_state(actual)
    if expected_bytes == actual_bytes:
        return None
    if expected.tick != actual.tick:
        return _difference("tick", expected.tick, actual.tick)
    if expected.phase != actual.phase:
        return _difference("phase", expected.phase.value, actual.phase.value)
    if len(expected.entities) != len(actual.entities):
        return _difference("entities/count", len(expected.entities), len(actual.entities))
    for index, (expected_entity, actual_entity) in enumerate(
        zip(expected.entities, actual.entities, strict=True)
    ):
        prefix = f"entities/{index}"
        if expected_entity.entity_id != actual_entity.entity_id:
            return _difference(
                f"{prefix}/entity_id",
                expected_entity.entity_id.value,
                actual_entity.entity_id.value,
            )
        if expected_entity.position.x != actual_entity.position.x:
            return _difference(
                f"{prefix}/position/x",
                expected_entity.position.x.value,
                actual_entity.position.x.value,
            )
        if expected_entity.position.y != actual_entity.position.y:
            return _difference(
                f"{prefix}/position/y",
                expected_entity.position.y.value,
                actual_entity.position.y.value,
            )
        if expected_entity.position.elevation != actual_entity.position.elevation:
            return _difference(
                f"{prefix}/position/elevation",
                expected_entity.position.elevation.value,
                actual_entity.position.elevation.value,
            )
    if (expected.map_geometry is None) != (actual.map_geometry is None):
        return _difference(
            "map_geometry/present",
            int(expected.map_geometry is not None),
            int(actual.map_geometry is not None),
        )
    if expected.map_geometry is not None and actual.map_geometry is not None:
        expected_bounds = expected.map_geometry.bounds
        actual_bounds = actual.map_geometry.bounds
        for field in ("minimum_x", "minimum_y", "maximum_x", "maximum_y"):
            expected_value = getattr(expected_bounds, field).value
            actual_value = getattr(actual_bounds, field).value
            if expected_value != actual_value:
                return _difference(f"map_geometry/bounds/{field}", expected_value, actual_value)
        if len(expected.map_geometry.obstacles) != len(actual.map_geometry.obstacles):
            return _difference(
                "map_geometry/obstacles/count",
                len(expected.map_geometry.obstacles),
                len(actual.map_geometry.obstacles),
            )
        for index, (expected_obstacle, actual_obstacle) in enumerate(
            zip(expected.map_geometry.obstacles, actual.map_geometry.obstacles, strict=True)
        ):
            prefix = f"map_geometry/obstacles/{index}"
            if expected_obstacle.obstacle_id != actual_obstacle.obstacle_id:
                return _difference(
                    f"{prefix}/obstacle_id",
                    expected_obstacle.obstacle_id.value,
                    actual_obstacle.obstacle_id.value,
                )
            if expected_obstacle.elevation != actual_obstacle.elevation:
                return _difference(
                    f"{prefix}/elevation",
                    expected_obstacle.elevation.value,
                    actual_obstacle.elevation.value,
                )
            for field in ("minimum_x", "minimum_y", "maximum_x", "maximum_y"):
                expected_value = getattr(expected_obstacle.bounds, field).value
                actual_value = getattr(actual_obstacle.bounds, field).value
                if expected_value != actual_value:
                    return _difference(f"{prefix}/bounds/{field}", expected_value, actual_value)
    if len(expected.movement_actions) != len(actual.movement_actions):
        return _difference(
            "movement_actions/count",
            len(expected.movement_actions),
            len(actual.movement_actions),
        )
    for index, (expected_action, actual_action) in enumerate(
        zip(expected.movement_actions, actual.movement_actions, strict=True)
    ):
        prefix = f"movement_actions/{index}"
        if expected_action.entity_id != actual_action.entity_id:
            return _difference(
                f"{prefix}/entity_id",
                expected_action.entity_id.value,
                actual_action.entity_id.value,
            )
        if expected_action.next_waypoint_index != actual_action.next_waypoint_index:
            return _difference(
                f"{prefix}/next_waypoint_index",
                expected_action.next_waypoint_index,
                actual_action.next_waypoint_index,
            )
        if expected_action.segment_progress != actual_action.segment_progress:
            return _difference(
                f"{prefix}/segment_progress",
                expected_action.segment_progress,
                actual_action.segment_progress,
            )
        if len(expected_action.path.waypoints) != len(actual_action.path.waypoints):
            return _difference(
                f"{prefix}/waypoints/count",
                len(expected_action.path.waypoints),
                len(actual_action.path.waypoints),
            )
        for waypoint_index, (expected_waypoint, actual_waypoint) in enumerate(
            zip(expected_action.path.waypoints, actual_action.path.waypoints, strict=True)
        ):
            waypoint_prefix = f"{prefix}/waypoints/{waypoint_index}"
            if expected_waypoint.x != actual_waypoint.x:
                return _difference(
                    f"{waypoint_prefix}/x",
                    expected_waypoint.x.value,
                    actual_waypoint.x.value,
                )
            if expected_waypoint.y != actual_waypoint.y:
                return _difference(
                    f"{waypoint_prefix}/y",
                    expected_waypoint.y.value,
                    actual_waypoint.y.value,
                )
            if expected_waypoint.elevation != actual_waypoint.elevation:
                return _difference(
                    f"{waypoint_prefix}/elevation",
                    expected_waypoint.elevation.value,
                    actual_waypoint.elevation.value,
                )
    if len(expected.policy_memory.entries) != len(actual.policy_memory.entries):
        return _difference(
            "policy_memory/count",
            len(expected.policy_memory.entries),
            len(actual.policy_memory.entries),
        )
    for index, (expected_memory, actual_memory) in enumerate(
        zip(expected.policy_memory.entries, actual.policy_memory.entries, strict=True)
    ):
        prefix = f"policy_memory/{index}"
        if expected_memory.entity_id != actual_memory.entity_id:
            return _difference(
                f"{prefix}/entity_id",
                expected_memory.entity_id.value,
                actual_memory.entity_id.value,
            )
        if expected_memory.value != actual_memory.value:
            return _difference(
                f"{prefix}/value", repr(expected_memory.value), repr(actual_memory.value)
            )
    if len(expected.policy_versions.entries) != len(actual.policy_versions.entries):
        return _difference(
            "policy_versions/count",
            len(expected.policy_versions.entries),
            len(actual.policy_versions.entries),
        )
    for index, (expected_version, actual_version) in enumerate(
        zip(expected.policy_versions.entries, actual.policy_versions.entries, strict=True)
    ):
        prefix = f"policy_versions/{index}"
        if expected_version.entity_id != actual_version.entity_id:
            return _difference(
                f"{prefix}/entity_id",
                expected_version.entity_id.value,
                actual_version.entity_id.value,
            )
        if expected_version.version != actual_version.version:
            return _difference(
                f"{prefix}/digest",
                expected_version.version.digest.hex(),
                actual_version.version.digest.hex(),
            )
    if expected.contacts.lifecycle_tick != actual.contacts.lifecycle_tick:
        return _difference(
            "contacts/lifecycle_tick",
            expected.contacts.lifecycle_tick,
            actual.contacts.lifecycle_tick,
        )
    if len(expected.contacts.estimates) != len(actual.contacts.estimates):
        return _difference(
            "contacts/count",
            len(expected.contacts.estimates),
            len(actual.contacts.estimates),
        )
    for index, (expected_contact, actual_contact) in enumerate(
        zip(expected.contacts.estimates, actual.contacts.estimates, strict=True)
    ):
        prefix = f"contacts/{index}"
        if expected_contact.owner_entity_id != actual_contact.owner_entity_id:
            return _difference(
                f"{prefix}/owner_entity_id",
                expected_contact.owner_entity_id.value,
                actual_contact.owner_entity_id.value,
            )
        if expected_contact.contact_id != actual_contact.contact_id:
            return _difference(
                f"{prefix}/contact_id",
                expected_contact.contact_id.value,
                actual_contact.contact_id.value,
            )
        for axis in ("x", "y", "elevation"):
            expected_value = getattr(expected_contact.estimated_position, axis).value
            actual_value = getattr(actual_contact.estimated_position, axis).value
            if expected_value != actual_value:
                return _difference(
                    f"{prefix}/estimated_position/{axis}", expected_value, actual_value
                )
        if expected_contact.uncertainty_radius != actual_contact.uncertainty_radius:
            return _difference(
                f"{prefix}/uncertainty_radius",
                expected_contact.uncertainty_radius.value,
                actual_contact.uncertainty_radius.value,
            )
        if expected_contact.confidence != actual_contact.confidence:
            return _difference(
                f"{prefix}/confidence_basis_points",
                expected_contact.confidence.basis_points,
                actual_contact.confidence.basis_points,
            )
        if expected_contact.last_observed_tick != actual_contact.last_observed_tick:
            return _difference(
                f"{prefix}/last_observed_tick",
                expected_contact.last_observed_tick,
                actual_contact.last_observed_tick,
            )
        for expected_field, actual_field in zip(
            expected_contact.provenance.fields,
            actual_contact.provenance.fields,
            strict=True,
        ):
            provenance_prefix = f"{prefix}/provenance/{expected_field.field.value}"
            if expected_field.field != actual_field.field:
                return _difference(
                    f"{provenance_prefix}/field",
                    expected_field.field.value,
                    actual_field.field.value,
                )
            if len(expected_field.evidence_event_ids) != len(actual_field.evidence_event_ids):
                return _difference(
                    f"{provenance_prefix}/evidence_event_ids/count",
                    len(expected_field.evidence_event_ids),
                    len(actual_field.evidence_event_ids),
                )
            for evidence_index, (expected_event_id, actual_event_id) in enumerate(
                zip(expected_field.evidence_event_ids, actual_field.evidence_event_ids, strict=True)
            ):
                if expected_event_id != actual_event_id:
                    return _difference(
                        f"{provenance_prefix}/evidence_event_ids/{evidence_index}",
                        expected_event_id.value,
                        actual_event_id.value,
                    )
    if expected.messages.next_sequence != actual.messages.next_sequence:
        return _difference(
            "messages/next_sequence",
            expected.messages.next_sequence,
            actual.messages.next_sequence,
        )
    if len(expected.messages.messages) != len(actual.messages.messages):
        return _difference(
            "messages/count",
            len(expected.messages.messages),
            len(actual.messages.messages),
        )
    for index, (expected_message, actual_message) in enumerate(
        zip(expected.messages.messages, actual.messages.messages, strict=True)
    ):
        prefix = f"messages/{index}"
        for field in (
            "message_id",
            "sender_entity_id",
            "recipient_entity_id",
            "channel",
            "send_tick",
            "delivery_tick",
            "expiry_tick",
            "sequence",
            "send_event_id",
        ):
            expected_value = getattr(expected_message, field)
            actual_value = getattr(actual_message, field)
            if expected_value != actual_value:
                if hasattr(expected_value, "value"):
                    expected_rendered = expected_value.value
                    actual_rendered = actual_value.value
                else:
                    expected_rendered = expected_value
                    actual_rendered = actual_value
                return _difference(f"{prefix}/{field}", expected_rendered, actual_rendered)
        if expected_message.payload != actual_message.payload:
            return _difference(
                f"{prefix}/payload",
                repr(expected_message.payload),
                repr(actual_message.payload),
            )
        if len(expected_message.provenance_event_ids) != len(actual_message.provenance_event_ids):
            return _difference(
                f"{prefix}/provenance_event_ids/count",
                len(expected_message.provenance_event_ids),
                len(actual_message.provenance_event_ids),
            )
        for provenance_index, (expected_event_id, actual_event_id) in enumerate(
            zip(
                expected_message.provenance_event_ids,
                actual_message.provenance_event_ids,
                strict=True,
            )
        ):
            if expected_event_id != actual_event_id:
                return _difference(
                    f"{prefix}/provenance_event_ids/{provenance_index}",
                    expected_event_id.value,
                    actual_event_id.value,
                )
    if len(expected.signals.signals) != len(actual.signals.signals):
        return _difference(
            "signals/count",
            len(expected.signals.signals),
            len(actual.signals.signals),
        )
    for index, (expected_signal, actual_signal) in enumerate(
        zip(expected.signals.signals, actual.signals.signals, strict=True)
    ):
        prefix = f"signals/{index}"
        for field in ("signal", "tick", "command_sequence", "source", "target_entity_id"):
            expected_value = getattr(expected_signal, field)
            actual_value = getattr(actual_signal, field)
            if expected_value != actual_value:
                if expected_value is None:
                    return _difference(f"{prefix}/{field}", "absent", "present")
                if actual_value is None:
                    return _difference(f"{prefix}/{field}", "present", "absent")
                if hasattr(expected_value, "value"):
                    expected_rendered = expected_value.value
                    actual_rendered = actual_value.value
                else:
                    expected_rendered = expected_value
                    actual_rendered = actual_value
                return _difference(f"{prefix}/{field}", expected_rendered, actual_rendered)
        if expected_signal.provenance_event_id != actual_signal.provenance_event_id:
            return _difference(
                f"{prefix}/provenance_event_id",
                expected_signal.provenance_event_id.value,
                actual_signal.provenance_event_id.value,
            )
    for kind in IdKind:
        expected_next_id = expected.id_allocator.next_ids[int(kind)]
        actual_next_id = actual.id_allocator.next_ids[int(kind)]
        if expected_next_id != actual_next_id:
            return _difference(
                f"id_allocator/{kind.name.lower()}", expected_next_id, actual_next_id
            )
    if expected.scheduled_events.next_sequence != actual.scheduled_events.next_sequence:
        return _difference(
            "scheduled_events/next_sequence",
            expected.scheduled_events.next_sequence,
            actual.scheduled_events.next_sequence,
        )
    if len(expected.scheduled_events.pending) != len(actual.scheduled_events.pending):
        return _difference(
            "scheduled_events/pending/count",
            len(expected.scheduled_events.pending),
            len(actual.scheduled_events.pending),
        )
    for index, (expected_event, actual_event) in enumerate(
        zip(expected.scheduled_events.pending, actual.scheduled_events.pending, strict=True)
    ):
        prefix = f"scheduled_events/pending/{index}"
        if expected_event.tick != actual_event.tick:
            return _difference(f"{prefix}/tick", expected_event.tick, actual_event.tick)
        if expected_event.sequence != actual_event.sequence:
            return _difference(f"{prefix}/sequence", expected_event.sequence, actual_event.sequence)
    if expected.random_streams.seed != actual.random_streams.seed:
        return _difference(
            "random_streams/seed",
            expected.random_streams.seed.value,
            actual.random_streams.seed.value,
        )
    for stream_id in RandomStreamId:
        expected_stream = expected.random_streams.stream_state(stream_id)
        actual_stream = actual.random_streams.stream_state(stream_id)
        prefix = f"random_streams/{stream_id.name.lower()}"
        if expected_stream.state != actual_stream.state:
            return _difference(f"{prefix}/state", expected_stream.state, actual_stream.state)
        if expected_stream.next_draw_index != actual_stream.next_draw_index:
            return _difference(
                f"{prefix}/next_draw_index",
                expected_stream.next_draw_index,
                actual_stream.next_draw_index,
            )
    return _byte_difference(expected_bytes, actual_bytes)


def _divergence_from_checkpoints(
    expected: AuthoritySnapshot, actual: AuthoritySnapshot
) -> DeterminismDivergence:
    expected_state = restore_authority_snapshot(expected)
    actual_state = restore_authority_snapshot(actual)
    if not isinstance(expected_state, MissionState) or not isinstance(actual_state, MissionState):
        raise ValueError("determinism comparison requires valid authority checkpoints")
    difference = first_canonical_state_difference(expected_state, actual_state)
    if difference is None:
        raise AssertionError("distinct checkpoint hashes require a state difference")
    return _divergence(expected.tick, expected.state_hash, actual.state_hash, difference)


def _divergence(
    tick: int,
    expected_hash: StateHash,
    actual_hash: StateHash,
    difference: CanonicalStateDifference,
) -> DeterminismDivergence:
    return DeterminismDivergence(tick, expected_hash, actual_hash, difference)


def _difference(path: str, expected: int | str, actual: int | str) -> CanonicalStateDifference:
    return CanonicalStateDifference(path, str(expected), str(actual))


def _byte_difference(expected: bytes, actual: bytes) -> CanonicalStateDifference:
    for index, (expected_byte, actual_byte) in enumerate(zip(expected, actual, strict=False)):
        if expected_byte != actual_byte:
            return _difference(
                f"canonical_state/bytes/{index}",
                f"0x{expected_byte:02x}",
                f"0x{actual_byte:02x}",
            )
    return _difference("canonical_state/bytes/length", len(expected), len(actual))
