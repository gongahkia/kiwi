"""Versioned immutable capability requirements for compiled policy entry points."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.dsl.bytecode import FunctionTable, FunctionTableEntry
from kiwi.dsl.core_ir import CoreDefinitionKind, CoreModule
from kiwi.dsl.ids import DefinitionId, FunctionId
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


def empty_capability_manifest(
    module: CoreModule, function_table: FunctionTable
) -> CapabilityManifest:
    """Create the M4 empty requirements manifest for canonical policy entries."""
    entries: list[EntryPointCapabilities] = []
    for definition in sorted(module.definitions, key=lambda item: item.definition_id.value):
        if definition.kind is not CoreDefinitionKind.POLICY:
            continue
        function_entry = _function_entry_for_definition(function_table, definition.definition_id)
        entries.append(EntryPointCapabilities(function_entry.function_id, function_entry.name))
    return CapabilityManifest(CAPABILITY_MANIFEST_VERSION, tuple(entries))


def _function_entry_for_definition(
    function_table: FunctionTable,
    definition_id: DefinitionId,
) -> FunctionTableEntry:
    for entry in function_table.entries:
        if entry.definition_id == definition_id:
            return entry
    raise AssertionError("policy definition has no compiled function-table entry")
