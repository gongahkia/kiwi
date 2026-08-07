# Contributing to KIWI // Terminal

KIWI is a deterministic squad-tactics game whose player policies are written
in a closed functional DSL. The compiler, VM, simulation, replay verifier,
trace queries, and content validation must remain headless; pygame-ce belongs
only to application and presentation packages.

## Setup

Use macOS or another supported development host with CPython 3.12 and `uv`:

```bash
uv sync --extra dev
make doctor
make check
```

`make check` verifies formatting, Ruff, mypy, and the test suite. Use
`make format` only when a formatter rewrite is wanted. The equivalent commands
are recorded in the `Makefile` and `README.md`.

## Focused workflows

Validate untrusted source and content without starting pygame:

```bash
uv run --extra dev python -m kiwi.cli validate path/to/kiwi.policy.json
uv run --extra dev python -m kiwi.cli validate path/to/policy.dtr
uv run --extra dev python -m kiwi.cli validate path/to/mission.dmission.json
```

The policy-project validator follows every declared project source, preserves
DSL diagnostic spans, confirms declared policy entries, and confines manifest
paths to the project root. It does not execute player source.

Run the deterministic Terminal drill locally with `make terminal`. Its manual
observer-led usability protocol is in `TESTING.md`; do not commit participant
data. `make benchmark` reports host-specific headless performance measurements
and is informational rather than a CI threshold.

## Change expectations

Start with the active GitHub issue and the relevant specifications. Keep the
smallest coherent diff, add focused tests for behavioral changes, and run the
narrowest useful test before `make check`. Inspect `git diff --check` and the
final diff before committing.

Authoritative code must preserve deterministic ordering, use no wall-clock,
host randomness, filesystem, or renderer state, and never execute player input
as Python. Changes to durable formats, language semantics, replay behavior, or
source provenance require their matching specifications and tests. Do not add
dependencies, weaken validation, or change compatibility policy without the
appropriate documented decision.
