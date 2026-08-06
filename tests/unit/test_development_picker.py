from __future__ import annotations

from pathlib import Path

from kiwi.content.fixtures import KernelFixture
from kiwi.dsl.source import SourceFile
from kiwi.ui.development_picker import discover_development_picker


def test_development_picker_discovers_selects_and_loads_in_canonical_order(tmp_path: Path) -> None:
    policy_root = tmp_path / "policies"
    fixture_root = tmp_path / "fixtures"
    nested = policy_root / "nested"
    nested.mkdir(parents=True)
    fixture_root.mkdir()
    (nested / "z.dtr").write_text("fn z() -> Int = 0", encoding="utf-8")
    (policy_root / "a.dtr").write_text("fn a() -> Int = 1", encoding="utf-8")
    fixture = fixture_root / "minimal.kfixture.json"
    fixture.write_text(
        '{"format":"kiwi-kernel-fixture","version":1,"id":"minimal",'
        '"tick_rate":30,"seed":7,"entities":{},"scheduled_triggers":[]}',
        encoding="utf-8",
    )

    picker = discover_development_picker((policy_root,), (fixture_root,))
    selected = picker.select_policy(nested / "z.dtr").select_fixture(fixture)
    policy = selected.load_selected_policy()
    loaded_fixture = selected.load_selected_fixture()

    assert tuple(option.label for option in picker.policies) == (
        "policies/a.dtr",
        "policies/nested/z.dtr",
    )
    assert picker.selected_policy == policy_root / "a.dtr"
    assert selected.selected_policy == nested / "z.dtr"
    assert isinstance(policy, SourceFile)
    assert policy.text == "fn z() -> Int = 0"
    assert isinstance(loaded_fixture, KernelFixture)
    assert loaded_fixture.fixture_id == "minimal"


def test_development_picker_allows_empty_explicit_roots(tmp_path: Path) -> None:
    policies = tmp_path / "policies"
    fixtures = tmp_path / "fixtures"
    policies.mkdir()
    fixtures.mkdir()

    picker = discover_development_picker((policies,), (fixtures,))

    assert picker.policies == ()
    assert picker.fixtures == ()
    assert picker.selected_policy is None
    assert picker.selected_fixture is None
