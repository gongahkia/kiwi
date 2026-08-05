from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import EntityId, IntentionId, PolicyInvocationId
from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import CompiledArtifact, compile_artifact
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.policy_result import MemoryField, MemorySchema
from kiwi.dsl.runtime_values import RecordValue, StringValue
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.types import BuiltinType
from kiwi.replay.comparison import (
    RunDifferenceKind,
    compare_policy_execution,
)
from kiwi.sim.arbitration import IntentionCandidate
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.events import IntentionEmitted
from kiwi.sim.policies import PolicyBinding, PolicyBindings
from kiwi.sim.runner import HeadlessRun, run_headless
from kiwi.sim.state import MissionState, add_entity

MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))


def test_policy_execution_comparison_reports_first_changed_evaluation_and_intention() -> None:
    expected, actual, entity_id = _runs("1s", "2s")

    comparison = compare_policy_execution(expected, actual)

    assert not comparison.matches
    assert comparison.evaluation_difference is not None
    assert comparison.evaluation_difference.kind is RunDifferenceKind.CHANGED
    assert comparison.evaluation_difference.key.tick == 0
    assert comparison.evaluation_difference.key.entity_id == entity_id
    assert comparison.intention_difference is not None
    assert comparison.intention_difference.kind is RunDifferenceKind.CHANGED
    assert comparison.intention_difference.key.tick == 0
    assert comparison.intention_difference.key.issuer_entity_id == entity_id
    assert comparison.intention_difference.key.policy_order == 0


def test_policy_execution_comparison_ignores_allocator_only_intention_ids() -> None:
    expected, actual, _ = _runs("1s", "1s")
    emitted_index = next(
        index for index, event in enumerate(actual.events) if isinstance(event, IntentionEmitted)
    )
    emitted = actual.events[emitted_index]
    assert isinstance(emitted, IntentionEmitted)
    rewritten_origin = replace(
        emitted.candidate.origin,
        intention_id=IntentionId(99),
        invocation_id=PolicyInvocationId(99),
    )
    rewritten = replace(
        emitted,
        candidate=IntentionCandidate(rewritten_origin, emitted.candidate.intention),
    )
    modified_actual = replace(
        actual,
        events=(*actual.events[:emitted_index], rewritten, *actual.events[emitted_index + 1 :]),
    )

    comparison = compare_policy_execution(expected, modified_actual)

    assert comparison.matches


def test_policy_execution_comparison_reports_removed_evaluation_and_intention() -> None:
    expected, _, entity_id = _runs("1s", "1s")
    initial = MissionState()
    actual = run_headless(
        initial,
        FixedTickClock(TickRate.HZ_30),
        1,
        (StartMission(CommandHeader(0, 1, CommandSource.SCENARIO)),),
    )

    comparison = compare_policy_execution(expected, actual)

    assert comparison.evaluation_difference is not None
    assert comparison.evaluation_difference.kind is RunDifferenceKind.REMOVED
    assert comparison.evaluation_difference.key.entity_id == entity_id
    assert comparison.intention_difference is not None
    assert comparison.intention_difference.kind is RunDifferenceKind.REMOVED
    assert comparison.intention_difference.key.issuer_entity_id == entity_id


def test_policy_execution_comparison_rejects_non_runs() -> None:
    expected, _, _ = _runs("1s", "1s")

    with pytest.raises(TypeError, match="HeadlessRun"):
        compare_policy_execution(expected, object())  # type: ignore[arg-type]


def _runs(
    expected_duration: str,
    actual_duration: str,
) -> tuple[HeadlessRun, HeadlessRun, EntityId]:
    initial, entity = add_entity(
        MissionState(),
        WorldPosition(WorldSubunits(0), WorldSubunits(0)),
    )
    expected_binding = _binding(entity.entity_id, expected_duration)
    actual_binding = _binding(entity.entity_id, actual_duration)
    command = StartMission(CommandHeader(0, 1, CommandSource.SCENARIO))
    expected = run_headless(
        initial,
        FixedTickClock(TickRate.HZ_30),
        1,
        (command,),
        policy_bindings=PolicyBindings((expected_binding,)),
    )
    actual = run_headless(
        initial,
        FixedTickClock(TickRate.HZ_30),
        1,
        (command,),
        policy_bindings=PolicyBindings((actual_binding,)),
    )
    return expected, actual, entity.entity_id


def _binding(entity_id: EntityId, duration: str) -> PolicyBinding:
    return PolicyBinding(
        entity_id,
        _policy_artifact(duration),
        FunctionId(0),
        MEMORY_SCHEMA,
        RecordValue("Memory", ("label",), (StringValue("initial"),)),
    )


def _policy_artifact(duration: str) -> CompiledArtifact:
    source = SourceFile(
        SourceFileId("comparison-policy.dtr"),
        "type SelfObservation = { entity_id: Int, position: Position }\n"
        "type Observation = { self: SelfObservation, tick: Int }\n"
        "type Memory = { label: String }\n"
        "type Wait = { duration: Duration }\n"
        "type Decision = { intentions: List<Wait>, memory: Memory }\n"
        "policy decide(observation: Observation, memory: Memory) -> Decision = "
        f"Decision {{ intentions = [Wait {{ duration = {duration} }}], memory = memory }}\n",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
