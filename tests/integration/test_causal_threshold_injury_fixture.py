from __future__ import annotations

from dataclasses import replace
from pathlib import Path

from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import EventId
from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import CompiledArtifact, compile_artifact
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.policy_result import MemoryField, MemorySchema
from kiwi.dsl.runtime_values import BooleanValue, RecordValue, StringValue
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.dsl.types import BuiltinType
from kiwi.dsl.vm import VMBranchSelection
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.conditions import InjurySeverity, OperativeCondition, OperativeConditionStore
from kiwi.sim.contacts import (
    ContactConfidence,
    ContactEstimate,
    ContactField,
    ContactFieldProvenance,
    ContactProvenance,
    ContactStore,
)
from kiwi.sim.covers import (
    CoverHeight,
    CoverIntegrity,
    CoverSegment,
    CoverSide,
    CoverSlot,
    CoverStore,
)
from kiwi.sim.events import (
    DamageApplied,
    EventKind,
    FireFired,
    InjuryChanged,
    IntentionEmitted,
    IntentionSelected,
    MovementProgressed,
    MovementRouteStarted,
    PolicyEvaluated,
    ProjectileImpacted,
)
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.intentions import FireIntention, MoveTowardIntention
from kiwi.sim.map_geometry import MapGeometry
from kiwi.sim.policies import PolicyBinding, PolicyBindings, invoke_policies
from kiwi.sim.runner import HeadlessRun, run_headless
from kiwi.sim.state import EntityState, MissionState, add_entity
from kiwi.sim.weapons import Ammunition, EquippedWeapon, WeaponStore
from kiwi.trace.capture import capture_run_trace
from kiwi.trace.model import CausalTrace, ConsequenceTrace, TraceEdgeKind, WorldEventTrace
from kiwi.trace.queries import ConsequenceChainExplanation, consequence_chain

PLAYER_POLICY_PATH = (
    Path(__file__).resolve().parents[1]
    / "fixtures"
    / "policies"
    / "causal_threshold_injury_policy.dtr"
)
ENEMY_POLICY_PATH = (
    Path(__file__).resolve().parents[1]
    / "fixtures"
    / "policies"
    / "causal_threshold_injury_enemy_policy.dtr"
)
TERMINAL_SCOUT_POLICY_PATH = (
    Path(__file__).resolve().parents[2] / "examples" / "policies" / "terminal" / "scout.dtr"
)
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PLAYER_MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("committed", BuiltinType.BOOL),))
ENEMY_MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("fired", BuiltinType.BOOL),))
TERMINAL_MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))
ADVANCE_THRESHOLD_TEXT = "contact.uncertainty_radius <= 1m"
MOVE_TEXT = "MoveToward { target = Position { x = 1m, y = 0m } }"
FIRE_TEXT = "Fire { target = Position { x = 0m, y = 0m }, weapon_id = 1 }"


def test_causal_threshold_injury_fixture_is_deterministic_and_traceable() -> None:
    state, player, enemy, bindings, player_source, enemy_source = _fixture_inputs()
    first = _run_fixture(state, bindings)
    second = _run_fixture(state, bindings)
    pre_evaluation = invoke_policies(
        state,
        bindings,
        capture_expression_trace=True,
        capture_branch_selection_trace=True,
        capture_observation_read_trace=True,
    )
    player_evaluation = _policy_evaluation(first, player)
    player_move = _emitted_for(first, player)
    enemy_fire = _emitted_for(first, enemy)
    player_selected = _selected_for(first, player_move)
    route = _only_event(first, MovementRouteStarted)
    fired = _only_event(first, FireFired)
    impact = _only_event(first, ProjectileImpacted)
    movement = next(
        event
        for event in reversed(first.events)
        if isinstance(event, MovementProgressed)
        and (event.header.tick, event.header.event_id.value)
        < (impact.header.tick, impact.header.event_id.value)
    )
    damage = _only_event(first, DamageApplied)
    injury = _only_event(first, InjuryChanged)
    trace = capture_run_trace(first, hash_canonical_state(first.state))
    consequence = _only_trace_consequence(trace)
    chain = consequence_chain(trace, consequence.node_id)
    traced_player = next(
        evaluation
        for evaluation in pre_evaluation.evaluations
        if evaluation.entity_id == player.entity_id
    )
    final_player = next(
        entity for entity in first.state.entities if entity.entity_id == player.entity_id
    )

    assert first == second
    assert hash_canonical_state(first.state) == hash_canonical_state(second.state)
    assert player_evaluation.validation.evaluation.observation.nearest_contact is not None
    assert player_evaluation.validation.evaluation.observation.visible_covers
    assert ADVANCE_THRESHOLD_TEXT in player_source.text
    assert traced_player.result.expression_traces
    assert tuple(trace.selection for trace in traced_player.result.branch_selection_traces) == (
        VMBranchSelection.ELSE,
        VMBranchSelection.SOME,
        VMBranchSelection.THEN,
    )
    assert traced_player.result.observation_read_traces
    threshold_start = player_source.text.index(ADVANCE_THRESHOLD_TEXT)
    assert any(
        trace.source_map_entry.span.start.value
        <= threshold_start
        < trace.source_map_entry.span.end.value
        for trace in traced_player.result.expression_traces
    )
    assert any(
        trace.path == ("nearest_contact", "uncertainty_radius")
        for trace in traced_player.result.observation_read_traces
    )
    assert isinstance(player_move.candidate.intention, MoveTowardIntention)
    assert player_move.candidate.origin.source_span == player_source.span(
        ByteOffset(player_source.text.index(MOVE_TEXT)),
        ByteOffset(player_source.text.index(MOVE_TEXT) + len(MOVE_TEXT)),
    )
    assert isinstance(enemy_fire.candidate.intention, FireIntention)
    assert enemy_fire.candidate.origin.source_span == enemy_source.span(
        ByteOffset(enemy_source.text.index(FIRE_TEXT)),
        ByteOffset(enemy_source.text.index(FIRE_TEXT) + len(FIRE_TEXT)),
    )
    assert route.header.parent_event_ids == (player_selected.header.event_id,)
    assert player.entity_id != enemy.entity_id
    assert final_player.position.x.value > 0
    assert fired.resolution.candidate.origin == enemy_fire.candidate.origin
    assert impact.impact.source_intention == enemy_fire.candidate.origin
    assert damage.header.parent_event_ids == (impact.header.event_id,)
    assert injury.header.parent_event_ids == (damage.header.event_id,)
    assert injury.resolution.injury_before is InjurySeverity.SEVERE
    assert injury.resolution.injury_after is InjurySeverity.INCAPACITATED
    world_nodes = {
        record.event_id: record.node_id
        for record in trace.records
        if isinstance(record, WorldEventTrace)
    }
    assert any(
        edge.source_node_id == world_nodes[movement.header.event_id]
        and edge.target_node_id == world_nodes[impact.header.event_id]
        and edge.kind is TraceEdgeKind.CONTRIBUTED_TO
        for edge in trace.edges
    )
    assert isinstance(chain, ConsequenceChainExplanation)
    assert tuple(
        record.event_kind
        for record in chain.causal_records[:3]
        if isinstance(record, WorldEventTrace)
    ) == (
        EventKind.INJURY_CHANGED,
        EventKind.DAMAGE_APPLIED,
        EventKind.PROJECTILE_IMPACTED,
    )


def test_terminal_scout_starts_with_an_explainable_advance_failure() -> None:
    state, player, _, bindings, _, _ = _fixture_inputs()
    player_source = _source(TERMINAL_SCOUT_POLICY_PATH)
    player_artifact = _compile(player_source)
    player_binding = PolicyBinding(
        player.entity_id,
        player_artifact,
        _entry_function_id(player_artifact),
        TERMINAL_MEMORY_SCHEMA,
        RecordValue("Memory", ("label",), (StringValue("scout"),)),
    )
    flawed_bindings = PolicyBindings((player_binding, bindings.entries[1]))
    first = _run_fixture(state, flawed_bindings)
    second = _run_fixture(state, flawed_bindings)
    pre_evaluation = invoke_policies(
        state,
        flawed_bindings,
        capture_expression_trace=True,
        capture_branch_selection_trace=True,
        capture_observation_read_trace=True,
    )
    move = _emitted_for(first, player)
    injury = _only_event(first, InjuryChanged)
    trace = capture_run_trace(first, hash_canonical_state(first.state))
    consequence = _only_trace_consequence(trace)
    chain = consequence_chain(trace, consequence.node_id)
    traced_player = next(
        evaluation
        for evaluation in pre_evaluation.evaluations
        if evaluation.entity_id == player.entity_id
    )

    assert first == second
    assert ADVANCE_THRESHOLD_TEXT in player_source.text
    threshold_start = player_source.text.index(ADVANCE_THRESHOLD_TEXT)
    assert any(
        trace.source_map_entry.span.start.value
        <= threshold_start
        < trace.source_map_entry.span.end.value
        for trace in traced_player.result.expression_traces
    )
    assert isinstance(move.candidate.intention, MoveTowardIntention)
    assert move.candidate.origin.source_span == player_source.span(
        ByteOffset(player_source.text.index(MOVE_TEXT)),
        ByteOffset(player_source.text.index(MOVE_TEXT) + len(MOVE_TEXT)),
    )
    assert tuple(trace.selection for trace in traced_player.result.branch_selection_traces) == (
        VMBranchSelection.SOME,
        VMBranchSelection.THEN,
    )
    assert any(
        trace.path == ("nearest_contact", "uncertainty_radius")
        for trace in traced_player.result.observation_read_traces
    )
    assert first.state.conditions.condition_for(player.entity_id).injury_severity is (
        InjurySeverity.INCAPACITATED
    )
    assert injury.resolution.source_intention != move.candidate.origin
    assert isinstance(chain, ConsequenceChainExplanation)
    assert tuple(
        record.event_kind
        for record in chain.causal_records[:3]
        if isinstance(record, WorldEventTrace)
    ) == (
        EventKind.INJURY_CHANGED,
        EventKind.DAMAGE_APPLIED,
        EventKind.PROJECTILE_IMPACTED,
    )


def _run_fixture(state: MissionState, bindings: PolicyBindings) -> HeadlessRun:
    return run_headless(
        state,
        FixedTickClock(TickRate.HZ_30),
        2,
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
        checkpoint_interval=1,
        policy_bindings=bindings,
    )


def _fixture_inputs() -> tuple[
    MissionState,
    EntityState,
    EntityState,
    PolicyBindings,
    SourceFile,
    SourceFile,
]:
    geometry = MapGeometry(
        WorldRectangle(
            WorldSubunits(-5_000),
            WorldSubunits(-5_000),
            WorldSubunits(5_000),
            WorldSubunits(5_000),
        )
    )
    state, player = add_entity(
        MissionState(map_geometry=geometry), WorldPosition(WorldSubunits(0), WorldSubunits(0))
    )
    state, enemy = add_entity(state, WorldPosition(WorldSubunits(2_500), WorldSubunits(0)))
    cover_id, allocator = state.id_allocator.allocate_cover()
    evidence_event_id, allocator = allocator.allocate_event()
    contact_id, allocator = allocator.allocate_contact()
    weapon_id, allocator = allocator.allocate_weapon()
    cover = CoverSegment(
        cover_id,
        WorldPosition(WorldSubunits(-500), WorldSubunits(-700)),
        WorldPosition(WorldSubunits(500), WorldSubunits(-700)),
        CoverHeight.HIGH,
        CoverIntegrity(10_000),
        (CoverSlot(0, WorldPosition(WorldSubunits(0), WorldSubunits(-350)), CoverSide.LEFT),),
    )
    contact = ContactEstimate(
        contact_id,
        player.entity_id,
        enemy.position,
        WorldSubunits(500),
        ContactConfidence(10_000),
        0,
        _contact_provenance(evidence_event_id),
    )
    state = replace(
        state,
        id_allocator=allocator,
        contacts=ContactStore((contact,)),
        covers=CoverStore((cover,)),
        conditions=OperativeConditionStore((OperativeCondition(player.entity_id, 1, 0),)),
        weapons=WeaponStore((EquippedWeapon(weapon_id, enemy.entity_id, Ammunition(1, 1)),)),
    )
    player_source = _source(PLAYER_POLICY_PATH)
    enemy_source = _source(ENEMY_POLICY_PATH)
    player_artifact = _compile(player_source)
    enemy_artifact = _compile(enemy_source)
    bindings = PolicyBindings(
        (
            PolicyBinding(
                player.entity_id,
                player_artifact,
                _entry_function_id(player_artifact),
                PLAYER_MEMORY_SCHEMA,
                RecordValue("Memory", ("committed",), (BooleanValue(False),)),
            ),
            PolicyBinding(
                enemy.entity_id,
                enemy_artifact,
                _entry_function_id(enemy_artifact),
                ENEMY_MEMORY_SCHEMA,
                RecordValue("Memory", ("fired",), (BooleanValue(False),)),
            ),
        )
    )
    return state, player, enemy, bindings, player_source, enemy_source


def _source(path: Path) -> SourceFile:
    return SourceFile(
        SourceFileId(path.relative_to(REPOSITORY_ROOT).as_posix()),
        path.read_text(encoding="utf-8"),
    )


def _compile(source: SourceFile) -> CompiledArtifact:
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))


def _entry_function_id(artifact: CompiledArtifact) -> FunctionId:
    assert len(artifact.capability_manifest.entries) == 1
    return artifact.capability_manifest.entries[0].function_id


def _policy_evaluation(run: HeadlessRun, entity: EntityState) -> PolicyEvaluated:
    return next(
        event
        for event in run.events
        if isinstance(event, PolicyEvaluated)
        and event.validation.evaluation.entity_id == entity.entity_id
    )


def _emitted_for(run: HeadlessRun, entity: EntityState) -> IntentionEmitted:
    return next(
        event
        for event in run.events
        if isinstance(event, IntentionEmitted)
        and event.candidate.origin.issuer_entity_id == entity.entity_id
    )


def _selected_for(run: HeadlessRun, emitted: IntentionEmitted) -> IntentionSelected:
    return next(
        event
        for event in run.events
        if isinstance(event, IntentionSelected)
        and event.resolution.candidate.origin == emitted.candidate.origin
    )


def _only_event[Event](run: HeadlessRun, event_type: type[Event]) -> Event:
    events = tuple(event for event in run.events if isinstance(event, event_type))
    assert len(events) == 1
    return events[0]


def _only_trace_consequence(trace: CausalTrace) -> ConsequenceTrace:
    consequences = tuple(record for record in trace.records if isinstance(record, ConsequenceTrace))
    assert len(consequences) == 1
    return consequences[0]


def _contact_provenance(event_id: EventId) -> ContactProvenance:
    return ContactProvenance(
        tuple(ContactFieldProvenance(field, (event_id,)) for field in ContactField)
    )
