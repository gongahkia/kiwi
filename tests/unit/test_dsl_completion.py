from __future__ import annotations

import pytest

from kiwi.ui.dsl_completion import dsl_completion_prefix, dsl_completion_suffix, dsl_completions


def test_dsl_completions_are_bounded_stable_and_match_the_identifier_prefix() -> None:
    source = "policy advance = Mov"
    offset = len(source)

    assert dsl_completion_prefix(source, offset) == "Mov"
    assert dsl_completions(source, offset) == ("MoveToward",)
    assert dsl_completion_suffix(source, offset, "MoveToward") == "eToward"


def test_dsl_completions_do_not_offer_every_symbol_without_an_identifier_prefix() -> None:
    assert dsl_completions("policy ", len("policy ")) == ()


def test_dsl_completion_rejects_invalid_cursor_and_mismatched_symbol() -> None:
    with pytest.raises(ValueError, match="outside source"):
        dsl_completion_prefix("policy", 7)
    with pytest.raises(ValueError, match="does not match"):
        dsl_completion_suffix("Mov", 3, "TakeCover")
