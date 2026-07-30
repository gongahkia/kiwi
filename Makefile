.PHONY: check doctor format format-check lint test type

check: format-check lint type test

doctor:
	uv run --extra dev python -m kiwi.cli doctor

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
