"""Read-only, single-construct Glasshouse language-guide state."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum


class GlasshouseTutorialConstruct(StrEnum):
    """The supported scout-policy constructs introduced by the Glasshouse guide."""

    POLICY = "policy"
    RECORD = "record"
    OPTION = "option"
    MATCH = "match"
    CONDITIONAL = "conditional"
    DISTANCE = "distance"
    LIST = "list"


@dataclass(frozen=True, slots=True)
class GlasshouseTutorialLesson:
    """One short lesson explaining exactly one shipped language construct."""

    construct: GlasshouseTutorialConstruct
    title: str
    code_lines: tuple[str, ...]
    explanation_lines: tuple[str, ...]
    try_line: str

    def __post_init__(self) -> None:
        if not isinstance(self.construct, GlasshouseTutorialConstruct):
            raise TypeError("Glasshouse tutorial lesson construct is invalid")
        if not isinstance(self.title, str) or not self.title:
            raise ValueError("Glasshouse tutorial lesson title must be text")
        _validate_lines(self.code_lines, "code")
        _validate_lines(self.explanation_lines, "explanation")
        if not isinstance(self.try_line, str) or not self.try_line:
            raise ValueError("Glasshouse tutorial lesson try line must be text")


@dataclass(frozen=True, slots=True)
class GlasshouseTutorial:
    """An immutable selected lesson from the fixed Glasshouse language guide."""

    lessons: tuple[GlasshouseTutorialLesson, ...]
    selected_lesson_index: int = 0

    def __post_init__(self) -> None:
        if not isinstance(self.lessons, tuple) or not self.lessons:
            raise ValueError("Glasshouse tutorial requires immutable lessons")
        if any(not isinstance(lesson, GlasshouseTutorialLesson) for lesson in self.lessons):
            raise TypeError("Glasshouse tutorial lessons are invalid")
        constructs = tuple(lesson.construct for lesson in self.lessons)
        if len(set(constructs)) != len(constructs):
            raise ValueError("Glasshouse tutorial constructs must be unique")
        if (
            not isinstance(self.selected_lesson_index, int)
            or isinstance(self.selected_lesson_index, bool)
            or not 0 <= self.selected_lesson_index < len(self.lessons)
        ):
            raise ValueError("Glasshouse tutorial selection is invalid")

    @property
    def selected_lesson(self) -> GlasshouseTutorialLesson:
        """Return the current lesson without consulting editor or authority state."""
        return self.lessons[self.selected_lesson_index]

    def select_construct(self, construct: GlasshouseTutorialConstruct) -> GlasshouseTutorial:
        """Select one fixed lesson without changing source, compilation, or authority."""
        if not isinstance(construct, GlasshouseTutorialConstruct):
            raise TypeError("Glasshouse tutorial construct is invalid")
        for index, lesson in enumerate(self.lessons):
            if lesson.construct is construct:
                return replace(self, selected_lesson_index=index)
        raise ValueError("Glasshouse tutorial construct is unavailable")

    def next_lesson(self) -> GlasshouseTutorial:
        """Advance through the fixed guide without wrapping or changing any policy."""
        if self.selected_lesson_index == len(self.lessons) - 1:
            return self
        return replace(self, selected_lesson_index=self.selected_lesson_index + 1)

    def previous_lesson(self) -> GlasshouseTutorial:
        """Return to the preceding guide lesson without wrapping or changing any policy."""
        if self.selected_lesson_index == 0:
            return self
        return replace(self, selected_lesson_index=self.selected_lesson_index - 1)


def _validate_lines(lines: tuple[str, ...], label: str) -> None:
    if not isinstance(lines, tuple) or not lines:
        raise ValueError(f"Glasshouse tutorial lesson {label} must be immutable non-empty text")
    if any(not isinstance(line, str) or not line for line in lines):
        raise ValueError(f"Glasshouse tutorial lesson {label} must contain text")


GLASSHOUSE_LANGUAGE_TUTORIAL = GlasshouseTutorial(
    (
        GlasshouseTutorialLesson(
            GlasshouseTutorialConstruct.POLICY,
            "1. POLICY",
            ("policy advance_on_precise_contact(...)",),
            (
                "A policy receives one observation and memory.",
                "It returns a Decision; it cannot move an operative itself.",
            ),
            "Read the parameters before changing the body.",
        ),
        GlasshouseTutorialLesson(
            GlasshouseTutorialConstruct.RECORD,
            "2. RECORD",
            ("contact.uncertainty_radius",),
            (
                "Records give named, typed fields to observations.",
                "Field access reads data; it never changes the contact.",
            ),
            "Inspect the uncertainty field used by Lark.",
        ),
        GlasshouseTutorialLesson(
            GlasshouseTutorialConstruct.OPTION,
            "3. OPTION",
            ("nearest_contact: Option<Contact>",),
            (
                "An Option says a value may be absent.",
                "Some holds a contact; None means no contact is available.",
            ),
            "Do not invent a contact when the value is None.",
        ),
        GlasshouseTutorialLesson(
            GlasshouseTutorialConstruct.MATCH,
            "4. MATCH",
            ("match observation.nearest_contact with", "| Some(contact) -> ...", "| None -> ..."),
            (
                "match handles the two Option cases explicitly.",
                "The contact name exists only in the Some branch.",
            ),
            "Keep both arms when revising the scout policy.",
        ),
        GlasshouseTutorialLesson(
            GlasshouseTutorialConstruct.CONDITIONAL,
            "5. IF",
            ("if precise then advance else wait",),
            (
                "if chooses one result from a true or false condition.",
                "Both branches must return the same type of value.",
            ),
            "Change the threshold, not one branch's return shape.",
        ),
        GlasshouseTutorialLesson(
            GlasshouseTutorialConstruct.DISTANCE,
            "6. DISTANCE",
            ("contact.uncertainty_radius <= 1m",),
            (
                "1m is a Distance value, not an untyped number.",
                "Distance comparisons require distance on both sides.",
            ),
            "Try a smaller distance to make Lark more cautious.",
        ),
        GlasshouseTutorialLesson(
            GlasshouseTutorialConstruct.LIST,
            "7. INTENTION LIST",
            ("intentions = [MoveToward { target = ... }]",),
            (
                "A list contains the policy's requested intentions.",
                "The simulation validates and resolves every request.",
            ),
            "Use [] when the policy should request no action.",
        ),
    )
)
