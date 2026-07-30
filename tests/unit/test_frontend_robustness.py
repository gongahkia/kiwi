from __future__ import annotations

from random import Random

from kiwi.dsl.debug import format_surface_module, format_tokens
from kiwi.dsl.lexer import lex
from kiwi.dsl.parser import parse
from kiwi.dsl.source import SourceFile, SourceFileId


def test_lexer_and_parser_do_not_crash_on_bounded_deterministic_inputs() -> None:
    generator = Random(0)
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()=,:-# \n@α"
    for case_index in range(256):
        length = generator.randrange(257)
        text = "".join(generator.choice(alphabet) for _ in range(length))
        source = SourceFile(SourceFileId(f"case-{case_index}.dtr"), text)

        parsed = parse(lex(source))

        assert parsed.module.span.file_id == source.file_id


def test_debug_output_is_deterministic_for_identical_source() -> None:
    source = SourceFile(
        SourceFileId("policy.dtr"),
        "fn helper(x: Int) -> Int = let value = x in if true then value else -1",
    )

    first_lexed = lex(source)
    second_lexed = lex(source)
    first_parsed = parse(first_lexed)
    second_parsed = parse(second_lexed)

    assert format_tokens(first_lexed.tokens) == format_tokens(second_lexed.tokens)
    assert format_surface_module(first_parsed.module) == format_surface_module(second_parsed.module)
