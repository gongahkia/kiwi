from __future__ import annotations

from pathlib import Path

from kiwi.ui.glasshouse_tutorial import (
    GLASSHOUSE_LANGUAGE_TUTORIAL,
    GlasshouseTutorialConstruct,
)


def test_glasshouse_language_tutorial_covers_each_shipped_scout_construct_once() -> None:
    tutorial = GLASSHOUSE_LANGUAGE_TUTORIAL
    scout_source = (
        Path(__file__).resolve().parents[2] / "examples" / "policies" / "glasshouse" / "scout.dtr"
    ).read_text(encoding="utf-8")

    assert tuple(lesson.construct for lesson in tutorial.lessons) == (
        GlasshouseTutorialConstruct.POLICY,
        GlasshouseTutorialConstruct.RECORD,
        GlasshouseTutorialConstruct.OPTION,
        GlasshouseTutorialConstruct.MATCH,
        GlasshouseTutorialConstruct.CONDITIONAL,
        GlasshouseTutorialConstruct.DISTANCE,
        GlasshouseTutorialConstruct.LIST,
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


def test_glasshouse_language_tutorial_navigation_is_bounded_and_non_authoritative() -> None:
    tutorial = GLASSHOUSE_LANGUAGE_TUTORIAL
    distance = tutorial.select_construct(GlasshouseTutorialConstruct.DISTANCE)
    final_lesson = tutorial.select_construct(GlasshouseTutorialConstruct.LIST)

    assert distance.selected_lesson_index == 5
    assert distance.selected_lesson.construct is GlasshouseTutorialConstruct.DISTANCE
    assert tutorial.previous_lesson() is tutorial
    assert final_lesson.next_lesson() is final_lesson
