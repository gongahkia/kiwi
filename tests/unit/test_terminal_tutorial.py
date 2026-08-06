from __future__ import annotations

from pathlib import Path

from kiwi.ui.terminal_tutorial import (
    TERMINAL_LANGUAGE_TUTORIAL,
    TerminalTutorialConstruct,
)


def test_terminal_language_tutorial_covers_each_shipped_scout_construct_once() -> None:
    tutorial = TERMINAL_LANGUAGE_TUTORIAL
    scout_source = (
        Path(__file__).resolve().parents[2] / "examples" / "policies" / "terminal" / "scout.dtr"
    ).read_text(encoding="utf-8")

    assert tuple(lesson.construct for lesson in tutorial.lessons) == (
        TerminalTutorialConstruct.POLICY,
        TerminalTutorialConstruct.RECORD,
        TerminalTutorialConstruct.OPTION,
        TerminalTutorialConstruct.MATCH,
        TerminalTutorialConstruct.CONDITIONAL,
        TerminalTutorialConstruct.DISTANCE,
        TerminalTutorialConstruct.LIST,
    )
    assert tutorial.selected_lesson.title == "1. POLICY"
    assert "cannot move an operative itself" in tutorial.selected_lesson.explanation_lines[1]
    for syntax in (
        "policy advance_on_precise_contact",
        "type Contact =",
        "Option<Contact>",
        "match observation.nearest_contact with",
        "if contact.uncertainty_radius <= 1m then",
        "intentions = [",
    ):
        assert syntax in scout_source


def test_terminal_language_tutorial_navigation_is_bounded_and_non_authoritative() -> None:
    tutorial = TERMINAL_LANGUAGE_TUTORIAL
    distance = tutorial.select_construct(TerminalTutorialConstruct.DISTANCE)
    final_lesson = tutorial.select_construct(TerminalTutorialConstruct.LIST)

    assert distance.selected_lesson_index == 5
    assert distance.selected_lesson.construct is TerminalTutorialConstruct.DISTANCE
    assert tutorial.previous_lesson() is tutorial
    assert final_lesson.next_lesson() is final_lesson
