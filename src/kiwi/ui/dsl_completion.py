"""Small deterministic completion catalogue for the closed player DSL."""

from __future__ import annotations

_DSL_COMPLETIONS = (
    "Aim",
    "Bool",
    "Decision",
    "Duration",
    "Int",
    "List",
    "Memory",
    "MoveToward",
    "None",
    "Observation",
    "Option",
    "Position",
    "SelfObservation",
    "Some",
    "String",
    "TakeCover",
    "Wait",
    "else",
    "false",
    "fn",
    "if",
    "in",
    "intentions",
    "let",
    "match",
    "memory",
    "policy",
    "true",
    "type",
    "with",
)


def dsl_completion_prefix(source: str, cursor_offset: int) -> str:
    """Return the identifier prefix immediately preceding one source cursor."""
    if not isinstance(source, str):
        raise TypeError("DSL completion source must be text")
    if not isinstance(cursor_offset, int) or isinstance(cursor_offset, bool):
        raise TypeError("DSL completion cursor offset must be an integer")
    if not 0 <= cursor_offset <= len(source):
        raise ValueError("DSL completion cursor offset is outside source")
    start = cursor_offset
    while start > 0 and _is_identifier_character(source[start - 1]):
        start -= 1
    return source[start:cursor_offset]


def dsl_completions(source: str, cursor_offset: int, *, limit: int = 4) -> tuple[str, ...]:
    """Return bounded stable DSL completions for the current identifier prefix."""
    if not isinstance(limit, int) or isinstance(limit, bool) or limit <= 0:
        raise ValueError("DSL completion limit must be positive")
    prefix = dsl_completion_prefix(source, cursor_offset)
    if not prefix:
        return ()
    return tuple(item for item in _DSL_COMPLETIONS if item.startswith(prefix))[:limit]


def dsl_completion_suffix(source: str, cursor_offset: int, completion: str) -> str:
    """Return the text needed to complete one offered DSL symbol at the cursor."""
    if not isinstance(completion, str) or not completion:
        raise ValueError("DSL completion must be non-empty text")
    prefix = dsl_completion_prefix(source, cursor_offset)
    if not completion.startswith(prefix):
        raise ValueError("DSL completion does not match the current prefix")
    return completion[len(prefix) :]


def _is_identifier_character(character: str) -> bool:
    return character == "_" or character.isalnum()
