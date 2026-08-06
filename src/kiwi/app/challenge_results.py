"""Local-only, versioned challenge result metrics and histograms."""

from __future__ import annotations

import json
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path

RESULT_HISTORY_FORMAT = "kiwi-challenge-results"
RESULT_HISTORY_VERSION = 1
MAX_RESULT_HISTORY = 512


class ChallengeOutcome(StrEnum):
    """The explicit tactical end state reported beside optimization metrics."""

    SUCCESS = "success"
    FAILURE = "failure"


@dataclass(frozen=True, slots=True)
class ChallengeResult:
    """One local completed run with no opaque composite score."""

    challenge_id: str
    run_hash: str
    outcome: ChallengeOutcome
    casualties: int
    ticks: int
    bytecode_bytes: int
    vm_instructions: int
    policy_evaluations: int

    def __post_init__(self) -> None:
        if not _is_identifier(self.challenge_id):
            raise ValueError("result challenge ID must be lowercase ASCII text")
        if not isinstance(self.run_hash, str) or len(self.run_hash) != 64:
            raise ValueError("result run hash must be a 64-character digest")
        if not isinstance(self.outcome, ChallengeOutcome):
            raise TypeError("result outcome is invalid")
        for value, label in (
            (self.casualties, "casualties"),
            (self.ticks, "ticks"),
            (self.bytecode_bytes, "bytecode bytes"),
            (self.vm_instructions, "VM instructions"),
            (self.policy_evaluations, "policy evaluations"),
        ):
            if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                raise ValueError(f"result {label} must be non-negative")


@dataclass(frozen=True, slots=True)
class HistogramBucket:
    """One inclusive integer bucket suitable for direct bitmap rendering."""

    minimum: int
    maximum: int
    count: int

    def __post_init__(self) -> None:
        if any(
            not isinstance(value, int) or isinstance(value, bool)
            for value in (self.minimum, self.maximum, self.count)
        ):
            raise TypeError("histogram bucket values must be integers")
        if self.minimum > self.maximum or self.count < 0:
            raise ValueError("histogram bucket bounds or count are invalid")


@dataclass(frozen=True, slots=True)
class ChallengeHistory:
    """A bounded local ledger ordered by append sequence."""

    results: tuple[ChallengeResult, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.results, tuple) or len(self.results) > MAX_RESULT_HISTORY:
            raise ValueError("challenge history must be a bounded immutable result tuple")
        if any(not isinstance(result, ChallengeResult) for result in self.results):
            raise TypeError("challenge history must contain challenge results")

    def append(self, result: ChallengeResult) -> ChallengeHistory:
        """Retain one newest local result, evicting only the oldest after the fixed cap."""
        if not isinstance(result, ChallengeResult):
            raise TypeError("challenge history append requires a challenge result")
        return ChallengeHistory((*self.results, result)[-MAX_RESULT_HISTORY:])

    def for_challenge(self, challenge_id: str) -> tuple[ChallengeResult, ...]:
        """Return append-ordered local records for one explicit challenge identity."""
        if not _is_identifier(challenge_id):
            raise ValueError("result challenge ID must be lowercase ASCII text")
        return tuple(result for result in self.results if result.challenge_id == challenge_id)

    def histogram(
        self, challenge_id: str, metric: str, bins: int = 8
    ) -> tuple[HistogramBucket, ...]:
        """Build deterministic equal-width integer buckets for one displayed metric."""
        if metric not in ("casualties", "ticks", "bytecode_bytes", "vm_instructions"):
            raise ValueError("result histogram metric is unsupported")
        if not isinstance(bins, int) or isinstance(bins, bool) or not 1 <= bins <= 32:
            raise ValueError("result histogram bin count must be between one and 32")
        values = tuple(getattr(result, metric) for result in self.for_challenge(challenge_id))
        if not values:
            return ()
        minimum = min(values)
        maximum = max(values)
        width = max(1, (maximum - minimum + 1 + bins - 1) // bins)
        buckets = [0] * bins
        for value in values:
            buckets[min(bins - 1, (value - minimum) // width)] += 1
        return tuple(
            HistogramBucket(minimum + index * width, minimum + (index + 1) * width - 1, count)
            for index, count in enumerate(buckets)
        )


def load_challenge_history(path: Path) -> ChallengeHistory:
    """Read a local result ledger or return an empty ledger when no file exists."""
    if not isinstance(path, Path):
        raise TypeError("result history path must be a Path")
    try:
        content = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ChallengeHistory()
    document = json.loads(content)
    if not isinstance(document, dict) or set(document) != {"format", "version", "results"}:
        raise ValueError("result history document fields are invalid")
    if document["format"] != RESULT_HISTORY_FORMAT or document["version"] != RESULT_HISTORY_VERSION:
        raise ValueError("result history document version is unsupported")
    raw_results = document["results"]
    if not isinstance(raw_results, list):
        raise ValueError("result history results must be a list")
    return ChallengeHistory(tuple(_decode_result(item) for item in raw_results))


def save_challenge_history(path: Path, history: ChallengeHistory) -> None:
    """Persist one local result ledger through the application filesystem boundary."""
    if not isinstance(path, Path):
        raise TypeError("result history path must be a Path")
    if not isinstance(history, ChallengeHistory):
        raise TypeError("result history save requires challenge history")
    path.parent.mkdir(parents=True, exist_ok=True)
    document = {
        "format": RESULT_HISTORY_FORMAT,
        "version": RESULT_HISTORY_VERSION,
        "results": [_encode_result(result) for result in history.results],
    }
    path.write_text(json.dumps(document, sort_keys=True, separators=(",", ":")), encoding="utf-8")


def _encode_result(result: ChallengeResult) -> dict[str, int | str]:
    return {
        "challenge_id": result.challenge_id,
        "run_hash": result.run_hash,
        "outcome": result.outcome.value,
        "casualties": result.casualties,
        "ticks": result.ticks,
        "bytecode_bytes": result.bytecode_bytes,
        "vm_instructions": result.vm_instructions,
        "policy_evaluations": result.policy_evaluations,
    }


def _decode_result(value: object) -> ChallengeResult:
    if not isinstance(value, dict) or set(value) != {
        "challenge_id",
        "run_hash",
        "outcome",
        "casualties",
        "ticks",
        "bytecode_bytes",
        "vm_instructions",
        "policy_evaluations",
    }:
        raise ValueError("result history entry fields are invalid")
    return ChallengeResult(
        _text(value["challenge_id"]),
        _text(value["run_hash"]),
        ChallengeOutcome(_text(value["outcome"])),
        _integer(value["casualties"]),
        _integer(value["ticks"]),
        _integer(value["bytecode_bytes"]),
        _integer(value["vm_instructions"]),
        _integer(value["policy_evaluations"]),
    )


def _text(value: object) -> str:
    if not isinstance(value, str):
        raise ValueError("result history text value is invalid")
    return value


def _integer(value: object) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError("result history integer value is invalid")
    return value


def _is_identifier(value: str) -> bool:
    return bool(value) and all(
        character.isascii() and (character.islower() or character.isdigit() or character == "_")
        for character in value
    )
