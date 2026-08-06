.PHONY: benchmark check doctor format format-check glasshouse lint test type

check: format-check lint type test

doctor:
	uv run --extra dev python -m kiwi.cli doctor

benchmark:
	uv run --extra dev python -m kiwi.cli benchmark examples/policies/typed_core.dtr tests/fixtures/minimal.kfixture.json --entry choose --arg true

glasshouse:
	uv run --extra dev python -m kiwi.glasshouse

format:
	uv run --extra dev ruff format .

format-check:
	uv run --extra dev ruff format --check .

lint:
	uv run --extra dev ruff check .

test:
	uv run --extra dev pytest

type:
	uv run --extra dev mypy src tests
