from __future__ import annotations

import pytest

from kiwi.dsl.ids import DefinitionId, SymbolId


def test_compiler_ids_are_typed_and_value_based() -> None:
    assert DefinitionId(3) == DefinitionId(3)
    assert SymbolId(3) == SymbolId(3)
    assert not isinstance(DefinitionId(3), SymbolId)


def test_compiler_ids_reject_negative_values() -> None:
    with pytest.raises(ValueError, match="definition ID"):
        DefinitionId(-1)
    with pytest.raises(ValueError, match="definition ID"):
        DefinitionId(True)
    with pytest.raises(ValueError, match="symbol ID"):
        SymbolId(-1)
    with pytest.raises(ValueError, match="symbol ID"):
        SymbolId("3")  # type: ignore[arg-type]
