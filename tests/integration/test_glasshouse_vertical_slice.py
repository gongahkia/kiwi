from __future__ import annotations

from dataclasses import dataclass, replace
from pathlib import Path

from kiwi.app.glasshouse_execution import (
    GlasshouseMissionExecution,
    build_glasshouse_mission_execution,
    build_glasshouse_mission_presentation,
)
from kiwi.app.glasshouse_hostiles import GLASSHOUSE_HOSTILE_LOADOUTS
from kiwi.app.glasshouse_players import GLASSHOUSE_PLAYER_LOADOUTS, PLAYER_MEMORY_SCHEMA
from kiwi.app.glasshouse_workbench import build_glasshouse_workbench
from kiwi.content.missions import MissionData, load_mission_file
from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
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
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.types import BuiltinType
from kiwi.replay.recording import RecordedReplay, record_headless_run
from kiwi.replay.source_archive import (
    HistoricalSourceFile,
    ReplaySourceArchive,
    build_source_archive,
)
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.conditions import OperativeCondition, OperativeConditionStore
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
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.map_geometry import MapGeometry
from kiwi.sim.policies import PolicyBinding, PolicyBindings
from kiwi.sim.state import EntityState, MissionState, add_entity
from kiwi.sim.weapons import Ammunition, EquippedWeapon, WeaponStore
from kiwi.trace.capture import capture_run_trace
from kiwi.trace.comparison import ConsequenceDifferenceKind
from kiwi.ui.glasshouse_debrief import GlasshouseDebrief, glasshouse_debrief
from kiwi.ui.glasshouse_revision import GlasshouseGuidedRevision, guided_source_revision
from kiwi.ui.glasshouse_tutorial import GLASSHOUSE_LANGUAGE_TUTORIAL, GlasshouseTutorialConstruct
from kiwi.ui.run_comparison import run_comparison_view

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MISSION_PATH = REPOSITORY_ROOT / "examples" / "missions" / "glasshouse.dmission.json"
SCOUT_PATH = REPOSITORY_ROOT / "examples" / "policies" / "glasshouse" / "scout.dtr"
ENEMY_PATH = (
    REPOSITORY_ROOT / "tests" / "fixtures" / "policies" / "causal_threshold_injury_enemy_policy.dtr"
)
ENEMY_MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("fired", BuiltinType.BOOL),))
IDENTITY = ("vertical-slice", "sim-v1", b"g" * 32)


@dataclass(frozen=True, slots=True)
class GlasshouseVerticalSliceFixture:
    initial_state: MissionState
    player: EntityState
    scout_source: SourceFile
    enemy_source: SourceFile
    enemy_binding: PolicyBinding
    commands: tuple[StartMission, ...]


def test_glasshouse_vertical_slice_accepts_the_complete_failure_to_revision_loop() -> None:
    workbench = build_glasshouse_workbench(_sources(_player_file_ids())).open_workbench()
    compiled_workbench = workbench.select_policy("scout").compile_selected()
    execution = build_glasshouse_mission_execution(
        _mission(),
        compiled_workbench,
        _sources(_hostile_file_ids()),
    )

    assert compiled_workbench.compile_output is not None
    assert compiled_workbench.compile_output.succeeded
    assert isinstance(execution, GlasshouseMissionExecution)
    active = execution.request_start().advance()
    assert build_glasshouse_mission_presentation(active).snapshot.phase == "active"
    assert (
        GLASSHOUSE_LANGUAGE_TUTORIAL.select_construct(
            GlasshouseTutorialConstruct.DISTANCE
        ).selected_lesson_index
        == 5
    )

    scout_artifact = compiled_workbench.compile_output.artifact
    assert scout_artifact is not None
    fixture = _fixture(scout_artifact)
    baseline_bindings = _bindings(fixture, scout_artifact)
    baseline = _record(fixture, baseline_bindings)
    repeated = _record(fixture, baseline_bindings)
    baseline_trace = capture_run_trace(baseline.run, hash_canonical_state(baseline.run.state))
    debrief = glasshouse_debrief(baseline_trace)
    archive = _source_archive(baseline, fixture, baseline_bindings)

    assert baseline == repeated
    assert isinstance(debrief, GlasshouseDebrief)
    guided = guided_source_revision(debrief, baseline_trace, archive, compiled_workbench)
    assert isinstance(guided, GlasshouseGuidedRevision)
    assert guided.workbench.selected_policy.role == "scout"
    assert guided.selected_span is not None

    threshold = guided.workbench.editor.buffer.text.index("<= 1m") + len("<= ")
    revised_workbench = guided.workbench.replace_editor(
        guided.workbench.editor.select(threshold, threshold + 2).insert_text("0m")
    ).compile_selected()
    revised_output = revised_workbench.compile_output
    assert revised_output is not None
    assert revised_output.succeeded
    assert revised_output.artifact is not None
    revised = _record(fixture, _bindings(fixture, revised_output.artifact))
    revised_trace = capture_run_trace(revised.run, hash_canonical_state(revised.run.state))
    comparison = run_comparison_view(baseline, revised, baseline_trace, revised_trace)

    assert comparison.compatibility.is_compatible
    assert comparison.compatibility.policy_differences
    assert comparison.policy_execution is not None and not comparison.policy_execution.matches
    assert comparison.consequences is not None
    assert tuple(difference.kind for difference in comparison.consequences.differences) == (
        ConsequenceDifferenceKind.REMOVED,
    )
    assert comparison.state_divergence is not None


def _mission() -> MissionData:
    mission = load_mission_file(MISSION_PATH)
    assert isinstance(mission, MissionData)
    return mission


def _player_file_ids() -> tuple[str, ...]:
    return tuple(loadout.policy_file_id for loadout in GLASSHOUSE_PLAYER_LOADOUTS)


def _hostile_file_ids() -> tuple[str, ...]:
    return tuple(loadout.policy_file_id for loadout in GLASSHOUSE_HOSTILE_LOADOUTS)


def _sources(file_ids: tuple[str, ...]) -> tuple[SourceFile, ...]:
    return tuple(
        SourceFile(SourceFileId(file_id), (REPOSITORY_ROOT / file_id).read_text(encoding="utf-8"))
        for file_id in file_ids
    )


def _fixture(scout_artifact: CompiledArtifact) -> GlasshouseVerticalSliceFixture:
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
        ContactProvenance(
            tuple(ContactFieldProvenance(field, (evidence_event_id,)) for field in ContactField)
        ),
    )
    state = replace(
        state,
        id_allocator=allocator,
        contacts=ContactStore((contact,)),
        covers=CoverStore((cover,)),
        conditions=OperativeConditionStore((OperativeCondition(player.entity_id, 1, 0),)),
        weapons=WeaponStore((EquippedWeapon(weapon_id, enemy.entity_id, Ammunition(1, 1)),)),
    )
    scout_source = _source(SCOUT_PATH)
    enemy_source = _source(ENEMY_PATH)
    enemy_artifact = _compile(enemy_source)
    enemy_binding = PolicyBinding(
        enemy.entity_id,
        enemy_artifact,
        _entry_function_id(enemy_artifact),
        ENEMY_MEMORY_SCHEMA,
        RecordValue("Memory", ("fired",), (BooleanValue(False),)),
    )
    return GlasshouseVerticalSliceFixture(
        state,
        player,
        scout_source,
        enemy_source,
        enemy_binding,
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
    )


def _bindings(
    fixture: GlasshouseVerticalSliceFixture, scout_artifact: CompiledArtifact
) -> PolicyBindings:
    return PolicyBindings(
        (
            PolicyBinding(
                fixture.player.entity_id,
                scout_artifact,
                _entry_function_id(scout_artifact),
                PLAYER_MEMORY_SCHEMA,
                RecordValue("Memory", ("label",), (StringValue("scout"),)),
            ),
            fixture.enemy_binding,
        )
    )


def _record(fixture: GlasshouseVerticalSliceFixture, bindings: PolicyBindings) -> RecordedReplay:
    application_build, simulation_version, mission_hash = IDENTITY
    return record_headless_run(
        fixture.initial_state,
        FixedTickClock(TickRate.HZ_30),
        2,
        application_build=application_build,
        simulation_version=simulation_version,
        mission_hash=mission_hash,
        commands=fixture.commands,
        policy_bindings=bindings,
    )


def _source_archive(
    recorded: RecordedReplay,
    fixture: GlasshouseVerticalSliceFixture,
    bindings: PolicyBindings,
) -> ReplaySourceArchive:
    sources = tuple(
        sorted((fixture.scout_source, fixture.enemy_source), key=lambda source: source.file_id)
    )
    return build_source_archive(
        recorded.replay,
        tuple(
            HistoricalSourceFile(source, _source_language_version(bindings, source))
            for source in sources
        ),
        bindings,
    )


def _source_language_version(bindings: PolicyBindings, source: SourceFile) -> int:
    for binding in bindings.entries:
        if binding.artifact.bytecode.header.source_file_id == source.file_id:
            return binding.artifact.bytecode.header.source_language_version
    raise AssertionError("vertical-slice source has no policy binding")


def _source(path: Path) -> SourceFile:
    return SourceFile(
        SourceFileId(path.relative_to(REPOSITORY_ROOT).as_posix()),
        path.read_text(encoding="utf-8"),
    )


def _compile(source: SourceFile) -> CompiledArtifact:
    parsed = parse(lex(source))
    checked = check(resolve(parsed.module))
    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))


def _entry_function_id(artifact: CompiledArtifact) -> FunctionId:
    assert len(artifact.capability_manifest.entries) == 1
    return artifact.capability_manifest.entries[0].function_id
