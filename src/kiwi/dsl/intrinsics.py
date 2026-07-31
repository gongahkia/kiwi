"""Closed deterministic standard-library intrinsic identifiers."""

from __future__ import annotations

from enum import IntEnum


class IntrinsicKind(IntEnum):
    """Stable bytecode tags for the bounded List intrinsic family."""

    LIST_MAP = 1
    LIST_FILTER = 2
    LIST_FOLD = 3
    LIST_FIND = 4
    LIST_MIN_BY = 5
    LIST_SORT_BY = 6


_LIST_INTRINSICS = (
    ("map", IntrinsicKind.LIST_MAP),
    ("filter", IntrinsicKind.LIST_FILTER),
    ("fold", IntrinsicKind.LIST_FOLD),
    ("find", IntrinsicKind.LIST_FIND),
    ("min_by", IntrinsicKind.LIST_MIN_BY),
    ("sort_by", IntrinsicKind.LIST_SORT_BY),
)


def list_intrinsic(name: str) -> IntrinsicKind | None:
    """Return one closed List intrinsic by its exact surface field name."""
    for candidate, kind in _LIST_INTRINSICS:
        if candidate == name:
            return kind
    return None
