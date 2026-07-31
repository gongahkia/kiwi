"""Canonical deployed-policy identities keyed by entity ID."""

from __future__ import annotations

from dataclasses import dataclass
from hashlib import blake2b

from kiwi.domain.ids import EntityId
from kiwi.dsl.bytecode_codec import encode_bytecode
from kiwi.dsl.compiler import CompiledArtifact
from kiwi.dsl.ids import FunctionId

POLICY_VERSION_DIGEST_BYTES = 32
_POLICY_VERSION_DOMAIN = b"KWI-POLICY-VERSION\x00"


@dataclass(frozen=True, slots=True)
class PolicyVersion:
    """A BLAKE2b identity of one compiled module and selected entry point."""

    digest: bytes

    def __post_init__(self) -> None:
        if not isinstance(self.digest, bytes):
            raise ValueError("policy version digest must be bytes")
        if len(self.digest) != POLICY_VERSION_DIGEST_BYTES:
            raise ValueError("policy version digest must be exactly 32 bytes")

    @classmethod
    def from_artifact(
        cls,
        artifact: CompiledArtifact,
        function_id: FunctionId,
    ) -> PolicyVersion:
        """Hash canonical bytecode and its selected policy entry point."""
        if not isinstance(artifact, CompiledArtifact):
            raise TypeError("policy version requires a compiled artifact")
        if not isinstance(function_id, FunctionId):
            raise TypeError("policy version requires a function ID")
        if function_id.value >= len(artifact.bytecode.functions):
            raise ValueError("policy version function is outside the bytecode module")
        digest = blake2b(digest_size=POLICY_VERSION_DIGEST_BYTES)
        digest.update(_POLICY_VERSION_DOMAIN)
        digest.update(encode_bytecode(artifact.bytecode))
        digest.update(function_id.value.to_bytes(8, "big"))
        return cls(digest.digest())


@dataclass(frozen=True, slots=True)
class EntityPolicyVersion:
    """One deployed compiled-policy version for a mission entity."""

    entity_id: EntityId
    version: PolicyVersion

    def __post_init__(self) -> None:
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("entity policy version requires an entity ID")
        if not isinstance(self.version, PolicyVersion):
            raise ValueError("entity policy version requires a policy version")


@dataclass(frozen=True, slots=True)
class PolicyVersionStore:
    """An immutable entity-ID-ordered sparse deployed-policy mapping."""

    entries: tuple[EntityPolicyVersion, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.entries, tuple):
            raise ValueError("policy version entries must be an immutable tuple")
        previous_id = 0
        for entry in self.entries:
            if not isinstance(entry, EntityPolicyVersion):
                raise ValueError("policy version entries must be entity policy versions")
            if entry.entity_id.value <= previous_id:
                raise ValueError("policy version entries must be unique and entity-ID ordered")
            previous_id = entry.entity_id.value

    def version_for(self, entity_id: EntityId) -> PolicyVersion | None:
        """Return one deployed version without relying on mapping iteration order."""
        if not isinstance(entity_id, EntityId):
            raise ValueError("policy version lookup requires an entity ID")
        for entry in self.entries:
            if entry.entity_id == entity_id:
                return entry.version
        return None

    def with_version(self, entity_id: EntityId, version: PolicyVersion) -> PolicyVersionStore:
        """Store one version without mutating or changing canonical entry order."""
        entry = EntityPolicyVersion(entity_id, version)
        retained = tuple(item for item in self.entries if item.entity_id != entity_id)
        return PolicyVersionStore(
            tuple(sorted((*retained, entry), key=lambda item: item.entity_id.value))
        )
