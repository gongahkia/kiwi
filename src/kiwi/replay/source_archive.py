"""Historical source sidecars bound to one canonical replay packet."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from hashlib import blake2b

from kiwi.domain.ids import EntityId
from kiwi.dsl.bytecode import BytecodeModule
from kiwi.dsl.bytecode_codec import BytecodeDecodeFailure, decode_bytecode, encode_bytecode
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.source import DEFAULT_MAX_SOURCE_BYTES, SourceFile, SourceFileId
from kiwi.replay.format import REPLAY_HASH_DIGEST_BYTES, ReplayPacket, hash_replay
from kiwi.sim.policies import PolicyBindings
from kiwi.sim.policy_versions import EntityPolicyVersion, PolicyVersion

SOURCE_ARCHIVE_MAGIC = b"KWI-SOURCE\x00"
SOURCE_ARCHIVE_VERSION = 1
MAX_ENCODED_SOURCE_ARCHIVE_BYTES = 64 * 1_024 * 1_024
MAX_HISTORICAL_SOURCE_FILES = 65_536
MAX_HISTORICAL_POLICIES = 65_536
MAX_SOURCE_FILE_ID_BYTES = 65_536
SOURCE_HASH_DIGEST_BYTES = 32


class SourceArchiveDecodeFailureCode(StrEnum):
    """Stable failures while decoding an untrusted historical-source sidecar."""

    TOO_LARGE = "HS001_TOO_LARGE"
    INVALID_MAGIC = "HS002_INVALID_MAGIC"
    UNSUPPORTED_VERSION = "HS003_UNSUPPORTED_VERSION"
    INVALID_STRUCTURE = "HS004_INVALID_STRUCTURE"
    TRAILING_BYTES = "HS005_TRAILING_BYTES"


@dataclass(frozen=True, slots=True)
class SourceArchiveDecodeFailure:
    """One structured non-throwing source-sidecar boundary failure."""

    code: SourceArchiveDecodeFailureCode
    message: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, SourceArchiveDecodeFailureCode):
            raise ValueError("source archive decode failure requires a code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("source archive decode failure requires a message")


@dataclass(frozen=True, slots=True)
class HistoricalSourceFile:
    """Exact source text and language version needed to navigate historical spans."""

    source: SourceFile
    source_language_version: int

    def __post_init__(self) -> None:
        if not isinstance(self.source, SourceFile):
            raise ValueError("historical source requires a source file")
        try:
            source_id_bytes = self.source.file_id.value.encode("utf-8")
            source_text_bytes = self.source.text.encode("utf-8")
        except UnicodeEncodeError as error:
            raise ValueError("historical source must be valid UTF-8") from error
        if len(source_id_bytes) > MAX_SOURCE_FILE_ID_BYTES:
            raise ValueError("historical source file ID exceeds the configured byte limit")
        if len(source_text_bytes) > DEFAULT_MAX_SOURCE_BYTES:
            raise ValueError("historical source text exceeds the configured byte limit")
        if (
            not isinstance(self.source_language_version, int)
            or isinstance(self.source_language_version, bool)
            or not 0 <= self.source_language_version <= _MAX_U32
        ):
            raise ValueError("historical source language version must fit unsigned 32-bit range")

    @property
    def source_hash(self) -> bytes:
        """Return the BLAKE2b-256 identity of the exact UTF-8 source text."""
        return blake2b(
            self.source.text.encode("utf-8"), digest_size=SOURCE_HASH_DIGEST_BYTES
        ).digest()


@dataclass(frozen=True, slots=True)
class HistoricalPolicySource:
    """One entity's deployed bytecode, source map, and selected entry point."""

    entity_id: EntityId
    version: PolicyVersion
    function_id: FunctionId
    bytecode: BytecodeModule

    def __post_init__(self) -> None:
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("historical policy source requires an entity ID")
        if not isinstance(self.version, PolicyVersion):
            raise ValueError("historical policy source requires a policy version")
        if not isinstance(self.function_id, FunctionId):
            raise ValueError("historical policy source requires a function ID")
        if not isinstance(self.bytecode, BytecodeModule):
            raise ValueError("historical policy source requires a bytecode module")
        if PolicyVersion.from_bytecode(self.bytecode, self.function_id) != self.version:
            raise ValueError("historical policy source bytecode does not match its policy version")


@dataclass(frozen=True, slots=True)
class ReplaySourceArchive:
    """One replay-hash-bound immutable source and bytecode provenance sidecar."""

    replay_hash: bytes
    sources: tuple[HistoricalSourceFile, ...]
    policies: tuple[HistoricalPolicySource, ...]

    def __post_init__(self) -> None:
        if (
            not isinstance(self.replay_hash, bytes)
            or len(self.replay_hash) != REPLAY_HASH_DIGEST_BYTES
        ):
            raise ValueError("source archive replay hash must be exactly 32 bytes")
        if not isinstance(self.sources, tuple):
            raise ValueError("source archive sources must be an immutable tuple")
        if len(self.sources) > MAX_HISTORICAL_SOURCE_FILES:
            raise ValueError("source archive source count exceeds the configured limit")
        if any(not isinstance(source, HistoricalSourceFile) for source in self.sources):
            raise ValueError("source archive sources must be historical source files")
        source_ids = tuple(source.source.file_id for source in self.sources)
        if source_ids != tuple(sorted(source_ids)) or _has_adjacent_duplicates(source_ids):
            raise ValueError("source archive sources must be unique and file-ID ordered")
        if not isinstance(self.policies, tuple):
            raise ValueError("source archive policies must be an immutable tuple")
        if len(self.policies) > MAX_HISTORICAL_POLICIES:
            raise ValueError("source archive policy count exceeds the configured limit")
        previous_entity_id = 0
        source_by_id = tuple((source.source.file_id, source) for source in self.sources)
        used_source_ids: list[SourceFileId] = []
        for policy in self.policies:
            if not isinstance(policy, HistoricalPolicySource):
                raise ValueError("source archive policies must be historical policy sources")
            if policy.entity_id.value <= previous_entity_id:
                raise ValueError("source archive policies must be unique and entity-ID ordered")
            previous_entity_id = policy.entity_id.value
            source = _source_for_file_id(source_by_id, policy.bytecode.header.source_file_id)
            if source is None:
                raise ValueError("historical policy source has no retained source text")
            if source.source_language_version != policy.bytecode.header.source_language_version:
                raise ValueError("historical source language version does not match bytecode")
            for entry in policy.bytecode.source_map.entries:
                source.source.positions_of(entry.span)
            used_source_ids.append(source.source.file_id)
        if _ordered_unique(used_source_ids) != source_ids:
            raise ValueError("source archive must retain exactly the policy source files")


type SourceArchiveDecodeResult = ReplaySourceArchive | SourceArchiveDecodeFailure


def build_source_archive(
    replay: ReplayPacket,
    sources: tuple[HistoricalSourceFile, ...],
    policy_bindings: PolicyBindings,
) -> ReplaySourceArchive:
    """Retain exact source and bytecode for the policy bindings recorded by one replay."""
    if not isinstance(replay, ReplayPacket):
        raise TypeError("source archive construction requires a ReplayPacket")
    if not isinstance(sources, tuple):
        raise ValueError("source archive sources must be an immutable tuple")
    if any(not isinstance(source, HistoricalSourceFile) for source in sources):
        raise ValueError("source archive sources must be historical source files")
    if not isinstance(policy_bindings, PolicyBindings):
        raise TypeError("source archive construction requires policy bindings")
    actual_versions = tuple(
        EntityPolicyVersion(binding.entity_id, binding.policy_version)
        for binding in policy_bindings.entries
    )
    if actual_versions != replay.policy_versions:
        raise ValueError("source archive bindings must match replay policy versions")
    ordered_sources = tuple(sorted(sources, key=lambda source: source.source.file_id))
    policies = tuple(
        HistoricalPolicySource(
            binding.entity_id,
            binding.policy_version,
            binding.function_id,
            binding.artifact.bytecode,
        )
        for binding in policy_bindings.entries
    )
    return ReplaySourceArchive(hash_replay(replay), ordered_sources, policies)


def source_archive_matches_replay(replay: ReplayPacket, archive: ReplaySourceArchive) -> bool:
    """Return whether an archive exactly supplies every policy version for one replay."""
    if not isinstance(replay, ReplayPacket):
        raise TypeError("source archive matching requires a ReplayPacket")
    if not isinstance(archive, ReplaySourceArchive):
        raise TypeError("source archive matching requires a ReplaySourceArchive")
    archived_versions = tuple(
        EntityPolicyVersion(policy.entity_id, policy.version) for policy in archive.policies
    )
    return (
        archive.replay_hash == hash_replay(replay) and archived_versions == replay.policy_versions
    )


def encode_source_archive(archive: ReplaySourceArchive) -> bytes:
    """Encode one validated historical-source sidecar in deterministic binary form."""
    if not isinstance(archive, ReplaySourceArchive):
        raise TypeError("source archive encoding requires a ReplaySourceArchive")
    chunks = [
        SOURCE_ARCHIVE_MAGIC,
        SOURCE_ARCHIVE_VERSION.to_bytes(2, "big"),
        archive.replay_hash,
        len(archive.sources).to_bytes(4, "big"),
    ]
    for source in archive.sources:
        source_id = source.source.file_id.value.encode("utf-8")
        text = source.source.text.encode("utf-8")
        chunks.extend(
            (
                len(source_id).to_bytes(4, "big"),
                source_id,
                source.source_language_version.to_bytes(4, "big"),
                source.source_hash,
                len(text).to_bytes(4, "big"),
                text,
            )
        )
    chunks.append(len(archive.policies).to_bytes(4, "big"))
    for policy in archive.policies:
        bytecode = encode_bytecode(policy.bytecode)
        chunks.extend(
            (
                policy.entity_id.value.to_bytes(8, "big"),
                policy.version.digest,
                policy.function_id.value.to_bytes(8, "big"),
                len(bytecode).to_bytes(4, "big"),
                bytecode,
            )
        )
    encoded = b"".join(chunks)
    if len(encoded) > MAX_ENCODED_SOURCE_ARCHIVE_BYTES:
        raise ValueError("encoded source archive exceeds the configured byte limit")
    return encoded


def decode_source_archive(data: bytes) -> SourceArchiveDecodeResult:
    """Decode one strict v1 historical-source sidecar without executing bytecode."""
    if not isinstance(data, bytes):
        raise TypeError("source archive decoding requires bytes")
    if len(data) > MAX_ENCODED_SOURCE_ARCHIVE_BYTES:
        return _decode_failure(
            SourceArchiveDecodeFailureCode.TOO_LARGE,
            "source archive exceeds the configured byte limit",
        )
    prefix_length = len(SOURCE_ARCHIVE_MAGIC) + 2
    if len(data) < prefix_length or data[: len(SOURCE_ARCHIVE_MAGIC)] != SOURCE_ARCHIVE_MAGIC:
        return _decode_failure(
            SourceArchiveDecodeFailureCode.INVALID_MAGIC,
            "source archive magic is invalid",
        )
    version = int.from_bytes(data[len(SOURCE_ARCHIVE_MAGIC) : prefix_length], "big")
    if version != SOURCE_ARCHIVE_VERSION:
        return _decode_failure(
            SourceArchiveDecodeFailureCode.UNSUPPORTED_VERSION,
            f"unsupported source archive format version {version}",
        )
    reader = _SourceArchiveReader(data, prefix_length)
    try:
        replay_hash = reader.read(REPLAY_HASH_DIGEST_BYTES)
        source_count = reader.read_unsigned(4)
        if source_count > MAX_HISTORICAL_SOURCE_FILES:
            raise _SourceArchiveFormatError("source archive source count is invalid")
        sources = tuple(_decode_source(reader) for _ in range(source_count))
        policy_count = reader.read_unsigned(4)
        if policy_count > MAX_HISTORICAL_POLICIES:
            raise _SourceArchiveFormatError("source archive policy count is invalid")
        policies = tuple(_decode_policy(reader) for _ in range(policy_count))
        if reader.remaining:
            return _decode_failure(
                SourceArchiveDecodeFailureCode.TRAILING_BYTES,
                "source archive has trailing bytes",
            )
        return ReplaySourceArchive(replay_hash, sources, policies)
    except _SourceArchiveFormatError as error:
        return _decode_failure(SourceArchiveDecodeFailureCode.INVALID_STRUCTURE, error.message)
    except ValueError as error:
        return _decode_failure(SourceArchiveDecodeFailureCode.INVALID_STRUCTURE, str(error))


def _decode_source(reader: _SourceArchiveReader) -> HistoricalSourceFile:
    source_id_bytes = reader.read_sized(MAX_SOURCE_FILE_ID_BYTES, "source file ID")
    source_language_version = reader.read_unsigned(4)
    expected_hash = reader.read(SOURCE_HASH_DIGEST_BYTES)
    source_text_bytes = reader.read_sized(DEFAULT_MAX_SOURCE_BYTES, "source text")
    try:
        source_id = source_id_bytes.decode("utf-8")
        text = source_text_bytes.decode("utf-8")
    except UnicodeDecodeError as error:
        raise _SourceArchiveFormatError("source archive text is not valid UTF-8") from error
    source = HistoricalSourceFile(
        SourceFile(SourceFileId(source_id), text), source_language_version
    )
    if source.source_hash != expected_hash:
        raise _SourceArchiveFormatError("historical source hash does not match source text")
    return source


def _decode_policy(reader: _SourceArchiveReader) -> HistoricalPolicySource:
    entity_id = EntityId(reader.read_unsigned(8))
    version = PolicyVersion(reader.read(32))
    function_id = FunctionId(reader.read_unsigned(8))
    bytecode_bytes = reader.read_sized(16 * 1_024 * 1_024, "bytecode")
    decoded = decode_bytecode(bytecode_bytes)
    if isinstance(decoded, BytecodeDecodeFailure):
        raise _SourceArchiveFormatError("historical policy bytecode is invalid")
    return HistoricalPolicySource(entity_id, version, function_id, decoded)


def _source_for_file_id(
    source_by_id: tuple[tuple[SourceFileId, HistoricalSourceFile], ...],
    file_id: SourceFileId,
) -> HistoricalSourceFile | None:
    for candidate_id, source in source_by_id:
        if candidate_id == file_id:
            return source
    return None


def _has_adjacent_duplicates(values: tuple[SourceFileId, ...]) -> bool:
    return any(first == second for first, second in zip(values, values[1:], strict=False))


def _ordered_unique(values: list[SourceFileId]) -> tuple[SourceFileId, ...]:
    ordered = tuple(sorted(values))
    return tuple(
        value for index, value in enumerate(ordered) if index == 0 or value != ordered[index - 1]
    )


def _decode_failure(
    code: SourceArchiveDecodeFailureCode,
    message: str,
) -> SourceArchiveDecodeFailure:
    return SourceArchiveDecodeFailure(code, message)


@dataclass(frozen=True, slots=True)
class _SourceArchiveFormatError(Exception):
    message: str


@dataclass(slots=True)
class _SourceArchiveReader:
    data: bytes
    offset: int

    @property
    def remaining(self) -> int:
        return len(self.data) - self.offset

    def read(self, count: int) -> bytes:
        if count > self.remaining:
            raise _SourceArchiveFormatError("source archive is truncated")
        result = self.data[self.offset : self.offset + count]
        self.offset += count
        return result

    def read_unsigned(self, width: int) -> int:
        return int.from_bytes(self.read(width), "big")

    def read_sized(self, maximum: int, label: str) -> bytes:
        size = self.read_unsigned(4)
        if size > maximum:
            raise _SourceArchiveFormatError(f"{label} exceeds the configured byte limit")
        return self.read(size)


_MAX_U32 = (1 << 32) - 1
