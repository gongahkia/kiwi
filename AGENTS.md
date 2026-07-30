# AGENTS.md

## Project intent

Kiwi is a Python and pygame-ce real-time squad tactics game in which players program autonomous squad logic using a small functional DSL. The compiler, deterministic VM, tactical simulation, replay system, and causal debugger are the core engineering work. The graphical client is a consumer of snapshots, not the authority.

Read `PRD.md`, `DECISIONS.md`, `ARCHITECTURE.md`, and the active milestone in `TODO.md` before making architectural changes.

## Non-negotiable invariants

1. Player programs are not Python and are never executed with `eval` or `exec`.
2. DSL programs are pure: immutable input, explicit memory, returned intentions.
3. The simulation, not the program or UI, decides outcomes.
4. Authoritative code does not read wall-clock time, OS randomness, filesystem state, or renderer state.
5. Deterministic ordering is explicit wherever order can affect results.
6. The compiler, VM, simulation, replay verifier, and trace queries run headlessly.
7. pygame imports are restricted to presentation and application-shell packages.
8. Important decisions retain machine-readable source provenance.
9. TODO items are completed only after their exit evidence passes.
10. No later milestone may be used to justify leaving the current milestone incomplete.

## Repository discipline

- Work in the milestone order defined by `TODO.md`.
- Select the smallest coherent unchecked task.
- Inspect existing code and tests before editing.
- Preserve a clean dependency direction.
- Add tests with each behavioural change.
- Update specifications when formats, interfaces, semantics, or commands change.
- Review the diff before committing.
- Commit each independently complete task or tightly coupled task group.
- Use imperative commit messages that describe the completed behaviour.

Do not create broad scaffolding for future milestones unless the current milestone requires it. Prefer a concrete representation with tests over speculative generic frameworks.

## Required dependency direction

Permitted high-level direction:

```text
domain <- dsl <- simulation <- replay/debugger <- application adapters
```

More precisely:

- `kiwi.domain` depends only on the Python standard library.
- `kiwi.dsl` may depend on `domain` value definitions but not pygame.
- `kiwi.sim` may depend on `domain` and compiled DSL interfaces but not pygame.
- `kiwi.replay` and `kiwi.trace` may depend on simulation event schemas.
- `kiwi.app` and `kiwi.render` may depend on all read-only public interfaces.
- Authoritative packages must not import from presentation packages.

Use architecture tests or import checks to enforce this boundary.

## Python rules

- Target Python 3.12 or later unless `DECISIONS.md` is updated.
- Use type annotations for public functions and durable data structures.
- Prefer frozen, slotted dataclasses or immutable tuples for authoritative values.
- Use enums and tagged dataclasses for variants; avoid magic strings in authority code.
- Do not rely on dictionary or set iteration unless canonical order is explicitly imposed.
- Avoid floating-point values in canonical state. Use integers, fixed-point quantities, rational representations, or carefully documented deterministic conversions.
- Do not catch broad `Exception` unless converting an external boundary failure into a typed error.
- Ordinary DSL errors must be structured values, not Python stack traces shown to players.
- Keep IO at boundaries. Core transforms should be testable as pure functions.
- Do not add dependencies without documenting why the standard library is insufficient.

## DSL rules

- Preserve source spans from tokenisation through bytecode and runtime traces.
- Every compiler stage must accept and return explicit typed structures.
- Diagnostics require stable codes, primary spans, messages, and optional notes.
- Bytecode execution has deterministic instruction and allocation budgets.
- No unbounded recursion in the MVP.
- Standard-library collection operations must be bounded and deterministic.
- Capability checking happens before runtime where practical.
- Language changes require parser, type, compiler, VM, diagnostics, fixture, and versioning updates as applicable.

## Simulation rules

- Use a fixed integer tick.
- Gather observations from a stable pre-evaluation state.
- Evaluate each policy against immutable inputs.
- Collect all intentions before authoritative resolution.
- Resolve in documented phases with canonical tie-breaking.
- Record random draws through named deterministic streams.
- Emit structured events for significant validations, arbitration decisions, actions, and outcomes.
- Hash canonical state at defined checkpoints.
- Keep rendering interpolation outside authoritative state.

## Causal-debugger rules

A textual log is not sufficient. Preserve identifiers and edges among:

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
