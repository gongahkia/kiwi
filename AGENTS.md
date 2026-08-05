# Instructions for Coding Agents

This repository is intended to be implementable by a local coding agent without relying on chat history.

## Required reading order

Before modifying code, read:

1. `README.md`
2. `PRD.md`
3. `TODO.md`
4. `docs/ARCHITECTURE.md`
5. `docs/TERMINAL_COMPATIBILITY.md`
6. `docs/RECORDING_FORMAT.md`
7. `docs/RENDERER_AND_EFFECTS.md`
8. `docs/BACKENDS.md`
9. `docs/PLUGIN_API.md`
10. `docs/TESTING.md`
11. `docs/SECURITY.md`
12. all accepted ADRs under `docs/adr/`

Then inspect the worktree and identify the earliest incomplete milestone in `TODO.md`.

## Operating rules

- Work on the smallest coherent slice that advances the earliest incomplete milestone.
- Do not begin a later milestone while an earlier exit criterion remains unsatisfied.
- Do not implement a browser engine, fake web browser, full shell, remote-session manager, or unrelated fantasy-computer environment.
- Do not make visual assets the project’s central architecture.
- Keep terminal semantics independent from LÖVE rendering.
- Keep backend I/O independent from terminal state mutation except through declared events.
- Keep effects read-only with respect to terminal semantics.
- Do not introduce global mutable singletons.
- Do not use wall-clock time directly in deterministic core or replay tests.
- Do not add native code to the LÖVE process in the initial PTY implementation; use the helper boundary.
- Do not silently broaden the compatibility claim.
- Do not advertise unsupported control sequences.
- Do not add host execution to sandbox mode.
- Do not weaken bounds checks for recordings or IPC to simplify development.

## Irreversible decisions

Create or update an ADR before making decisions that would be costly to reverse, including:

- public recording format changes;
- PTY helper protocol changes;
- public plugin API changes;
- public embedding API changes;
- cell-model representation changes that affect recordings or plugins;
- compatibility-profile promises;
- child-process shutdown semantics;
- persistent configuration schema changes.

If an ADR requires owner approval and no accepted direction exists, stop before implementation and present:

1. the exact decision;
2. two or three viable options;
3. trade-offs;
4. the recommended option;
5. the smallest work that remains unblocked.

## Testing expectations

Every behavioural change requires tests at the lowest useful layer.

Prefer:

- unit tests for isolated transitions;
- property tests for chunking, replay, and invariants;
- golden state snapshots for representative streams;
- integration tests for the PTY helper;
- benchmarks for renderer and parser regressions.

Do not rely primarily on screenshots for terminal correctness.

## Progress reporting

At the end of a slice, report:

- files changed;
- behaviour implemented;
- tests added and commands run;
- current milestone status;
- remaining blockers or risks;
- the next smallest safe slice.

Do not claim completion unless the relevant exit criteria pass.

## Code quality

- source span;
- function invocation;
- observation field read;
- intermediate value;
- branch or pattern selected;
- intention emitted;
- validation or arbitration decision;
- world event;
- damage, injury, death, or objective consequence.

Trace levels may reduce retained detail, but summary traces must still explain major outcomes.

## Verification

The repository should expose stable commands, preferably through `make`, `just`, or documented Python invocations. At minimum, milestones must eventually support:

```bash
python -m pytest
python -m ruff check .
python -m ruff format --check .
python -m mypy src tests
python -m kiwi.cli compile examples/policies/basic.dtr
python -m kiwi.cli simulate fixtures/glasshouse.json --headless
python -m kiwi.cli replay verify runs/example.drun
```

Use only commands actually configured in the repository. Update this file and `README.md` when the canonical commands change.

Current Milestone 4 headless commands are:

```bash
python -m kiwi.cli compile examples/policies/typed_core.dtr
python -m kiwi.cli compile examples/policies/typed_core.dtr --output /tmp/typed_core.kbc
python -m kiwi.cli disassemble examples/policies/typed_core.dtr
python -m kiwi.cli run-policy examples/policies/typed_core.dtr choose --arg true
python -m kiwi.cli trace-query path/to/run.ktrace why-selected 1
```

## Definition of done

A task is complete only when:

- its implementation is coherent and scoped;
- relevant unit and integration tests pass;
- deterministic implications were considered;
- diagnostics and source provenance remain valid;
- documentation is updated where required;
- no temporary debug code or generated junk remains;
- the diff contains no unrelated edits;
- the documented task exit evidence is available;
- the repository is committed at a valid rollback point.

## When to ask the user

Do not ask about routine choices that can be resolved from the documents, tests, primary documentation, or the smallest reversible design.

Stop and ask before:

- changing a settled decision;
- choosing an irreversible save or bytecode compatibility policy;
- adding a dependency with licensing or distribution consequences;
- weakening deterministic or causal-debugging guarantees;
- expanding direct player control;
- materially changing the product loop;
- committing to a visual fiction that constrains core mechanics;
- deleting or migrating user-authored content without a compatibility plan.
