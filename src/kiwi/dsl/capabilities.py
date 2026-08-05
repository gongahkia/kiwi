"""Versioned immutable capability requirements for compiled policy entry points."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.dsl.bytecode import FunctionTable, FunctionTableEntry
from kiwi.dsl.core_ir import (
    CoreBinary,
    CoreCall,
    CoreDefinitionKind,
    CoreExpression,
    CoreFieldAccess,
    CoreIf,
    CoreIntrinsicCall,
    CoreLambda,
    CoreLet,
    CoreList,
    CoreMatch,
    CoreMatchNoneArm,
    CoreMatchSomeArm,
    CoreModule,
    CoreNegate,
    CoreRecord,
    CoreSome,
)
from kiwi.dsl.ids import DefinitionId, FunctionId
from kiwi.dsl.intrinsics import IntrinsicKind
from kiwi.dsl.source import SourceSpan

CAPABILITY_MANIFEST_VERSION = 1


@dataclass(frozen=True, slots=True)
class CapabilityId:
    """A closed-format future tactical capability identifier."""

    value: str

    def __post_init__(self) -> None:
        if (
            not isinstance(self.value, str)
            or not self.value
            or not self.value.isascii()
            or not self.value.isidentifier()
            or self.value != self.value.lower()
        ):
            raise ValueError("capability ID must be a non-empty lowercase ASCII identifier")


MOVE_TOWARD_CAPABILITY = CapabilityId("move_toward")
TAKE_COVER_CAPABILITY = CapabilityId("take_cover")
WAIT_CAPABILITY = CapabilityId("wait")


@dataclass(frozen=True, slots=True)
class CapabilityRequirement:
    """One source-linked capability requirement for a policy entry point."""

    capability: CapabilityId
    primary_span: SourceSpan

    def __post_init__(self) -> None:
        if not isinstance(self.capability, CapabilityId):
            raise ValueError("capability requirement must contain a capability ID")
        if not isinstance(self.primary_span, SourceSpan):
            raise ValueError("capability requirement must contain a source span")


@dataclass(frozen=True, slots=True)
class EntryPointCapabilities:
    """Canonical requirements for one compiled policy entry point."""

    function_id: FunctionId
    name: str
    requirements: tuple[CapabilityRequirement, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.function_id, FunctionId):
            raise ValueError("entry capability function ID must be a function ID")
        if not isinstance(self.name, str) or not self.name:
            raise ValueError("entry capability name must be non-empty")
        if not isinstance(self.requirements, tuple):
            raise ValueError("entry capability requirements must be an immutable tuple")
        if any(
            not isinstance(requirement, CapabilityRequirement) for requirement in self.requirements
        ):
            raise ValueError("entry capability requirements must be requirements")
        capability_ids = tuple(requirement.capability.value for requirement in self.requirements)
        if capability_ids != tuple(sorted(capability_ids)) or len(set(capability_ids)) != len(
            capability_ids
        ):
            raise ValueError("entry capability requirements must be unique and lexically ordered")


@dataclass(frozen=True, slots=True)
class CapabilityManifest:
    """Versioned, source-linked requirements outside raw bytecode encoding."""

    version: int
    entries: tuple[EntryPointCapabilities, ...]

    def __post_init__(self) -> None:
        if (
            not isinstance(self.version, int)
            or isinstance(self.version, bool)
            or self.version != CAPABILITY_MANIFEST_VERSION
        ):
            raise ValueError("unsupported capability manifest version")
        if not isinstance(self.entries, tuple):
            raise ValueError("capability manifest entries must be an immutable tuple")
        if any(not isinstance(entry, EntryPointCapabilities) for entry in self.entries):
            raise ValueError("capability manifest entries must be entry capabilities")
        function_ids = tuple(entry.function_id.value for entry in self.entries)
        if function_ids != tuple(sorted(function_ids)) or len(set(function_ids)) != len(
            function_ids
        ):
            raise ValueError("capability manifest entries must be unique and function-ID ordered")


def capability_manifest(module: CoreModule, function_table: FunctionTable) -> CapabilityManifest:
    """Create source-linked capability requirements for canonical policy entries."""
    entries: list[EntryPointCapabilities] = []
    for definition in sorted(module.definitions, key=lambda item: item.definition_id.value):
        if definition.kind is not CoreDefinitionKind.POLICY:
            continue
        function_entry = _function_entry_for_definition(function_table, definition.definition_id)
        entries.append(
            EntryPointCapabilities(
                function_entry.function_id,
                function_entry.name,
                _requirements_for_expression(definition.body),
            )
        )
    return CapabilityManifest(CAPABILITY_MANIFEST_VERSION, tuple(entries))


def _requirements_for_expression(expression: CoreExpression) -> tuple[CapabilityRequirement, ...]:
    requirements: list[CapabilityRequirement] = []
    for candidate in _walk_expressions(expression):
        capability = _capability_for_expression(candidate)
        if capability is None or any(
            requirement.capability == capability for requirement in requirements
        ):
            continue
        requirements.append(CapabilityRequirement(capability, candidate.span))
    return tuple(sorted(requirements, key=lambda requirement: requirement.capability.value))


def _capability_for_expression(expression: CoreExpression) -> CapabilityId | None:
    if isinstance(expression, CoreRecord):
        return _capability_for_record_type(expression.type_name)
    if isinstance(expression, CoreIntrinsicCall) and expression.intrinsic in {
        IntrinsicKind.COVER_NEAREST_SAFE,
        IntrinsicKind.COVER_SEEK,
    }:
        return TAKE_COVER_CAPABILITY
    return None


def _capability_for_record_type(type_name: str) -> CapabilityId | None:
    if type_name == "MoveToward":
        return MOVE_TOWARD_CAPABILITY
    if type_name == "TakeCover":
        return TAKE_COVER_CAPABILITY
    if type_name == "Wait":
        return WAIT_CAPABILITY
    return None


def _walk_expressions(expression: CoreExpression) -> tuple[CoreExpression, ...]:
    descendants: list[CoreExpression] = [expression]
    if isinstance(expression, CoreSome):
        descendants.extend(_walk_expressions(expression.value))
    elif isinstance(expression, CoreList):
        for element in expression.elements:
            descendants.extend(_walk_expressions(element))
    elif isinstance(expression, CoreLambda):
        descendants.extend(_walk_expressions(expression.body))
    elif isinstance(expression, CoreMatch):
        descendants.extend(_walk_expressions(expression.subject))
        for arm in expression.arms:
            if isinstance(arm, (CoreMatchSomeArm, CoreMatchNoneArm)):
                descendants.extend(_walk_expressions(arm.body))
    elif isinstance(expression, CoreRecord):
        for field in expression.fields:
            descendants.extend(_walk_expressions(field.value))
    elif isinstance(expression, CoreNegate):
        descendants.extend(_walk_expressions(expression.operand))
    elif isinstance(expression, CoreBinary):
        descendants.extend(_walk_expressions(expression.left))
        descendants.extend(_walk_expressions(expression.right))
    elif isinstance(expression, CoreCall):
        descendants.extend(_walk_expressions(expression.callee))
        for argument in expression.arguments:
            descendants.extend(_walk_expressions(argument))
    elif isinstance(expression, CoreIntrinsicCall):
        for argument in expression.arguments:
            descendants.extend(_walk_expressions(argument))
    elif isinstance(expression, CoreFieldAccess):
        descendants.extend(_walk_expressions(expression.record))
    elif isinstance(expression, CoreLet):
        descendants.extend(_walk_expressions(expression.value))
        descendants.extend(_walk_expressions(expression.body))
    elif isinstance(expression, CoreIf):
        descendants.extend(_walk_expressions(expression.condition))
        descendants.extend(_walk_expressions(expression.then_branch))
        descendants.extend(_walk_expressions(expression.else_branch))
    return tuple(descendants)


def _function_entry_for_definition(
    function_table: FunctionTable,
    definition_id: DefinitionId,
) -> FunctionTableEntry:
    for entry in function_table.entries:
        if entry.definition_id == definition_id:
            return entry
    raise AssertionError("policy definition has no compiled function-table entry")
