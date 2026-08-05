"""Closed deterministic standard-library intrinsic identifiers."""

from __future__ import annotations

from enum import IntEnum


class IntrinsicKind(IntEnum):
    """Stable bytecode tags for the bounded standard-library intrinsic set."""

    LIST_MAP = 1
    LIST_FILTER = 2
    LIST_FOLD = 3
    LIST_FIND = 4
    LIST_MIN_BY = 5
    LIST_SORT_BY = 6
    COVER_EXPOSURE = 7
    COVER_ROUTE_COST = 8
    COVER_NEAREST_SAFE = 9
    COVER_SEEK = 10


_LIST_INTRINSICS = (
    ("map", IntrinsicKind.LIST_MAP),
    ("filter", IntrinsicKind.LIST_FILTER),
    ("fold", IntrinsicKind.LIST_FOLD),
    ("find", IntrinsicKind.LIST_FIND),
    ("min_by", IntrinsicKind.LIST_MIN_BY),
    ("sort_by", IntrinsicKind.LIST_SORT_BY),
)

_COVER_INTRINSICS = (
    ("exposure", IntrinsicKind.COVER_EXPOSURE),
    ("route_cost", IntrinsicKind.COVER_ROUTE_COST),
    ("nearest_safe", IntrinsicKind.COVER_NEAREST_SAFE),
    ("seek", IntrinsicKind.COVER_SEEK),
)


def list_intrinsic(name: str) -> IntrinsicKind | None:
    """Return one closed List intrinsic by its exact surface field name."""
    for candidate, kind in _LIST_INTRINSICS:
        if candidate == name:
            return kind
    return None


def cover_intrinsic(name: str) -> IntrinsicKind | None:
    """Return one closed Cover intrinsic by its exact surface field name."""
    for candidate, kind in _COVER_INTRINSICS:
        if candidate == name:
            return kind
    return None
