# Codex Handoff

## Initial repository prompt

Use this after placing the documentation files in a new repository:

```text
Read AGENTS.md, README.md, PRD.md, DECISIONS.md, ARCHITECTURE.md, DSL_SPEC.md,
SIMULATION_SPEC.md, CAUSAL_DEBUGGER.md, TESTING.md, and TODO.md.

This repository is a fresh implementation of Doctrine: a Python and pygame-ce
real-time squad tactics game where player-authored programs are written in a
separate functional DSL. The compiler, deterministic VM, headless simulation,
replay verifier, and causal debugger are the primary systems. Do not implement
player programs with Python eval/exec, and do not make pygame authoritative.

Begin with Milestone 0 only. Inspect the local environment and initialise the
smallest repository skeleton that satisfies Milestone 0. Select and document the
canonical Python environment, formatting, linting, type-checking, testing, and
command-entry workflow. Prefer a src layout and pyproject.toml. Add architecture
boundary tests. Do not implement later DSL or game features beyond minimal stubs
needed to prove the skeleton.

Before editing, state the Milestone 0 plan and verification commands. After the
work, run every Milestone 0 exit check, update TODO.md only for tasks genuinely
completed, review the diff, and create a descriptive git commit. If a genuine
blocking product, licensing, dependency, or irreversible format decision arises,
stop before making it and report the options and trade-offs.
```

## Continuing after the first prompt

Use a milestone-driven goal rather than an undifferentiated request to “finish the game.” The active agent should:

1. Read the documents relevant to the current milestone.
2. Inspect code and recent commits.
3. Select the first incomplete task.
4. Define its verification evidence.
5. Implement the smallest coherent slice.
6. Run focused and milestone checks.
7. Update TODO and specifications.
8. Commit a valid rollback point.
9. Proceed only after the milestone exit criteria pass.

## Recommended session sequence

### Session 1 — Repository skeleton

Complete Milestone 0 only. Establish packaging, commands, CI, type checking, test structure, import boundaries, and a minimal headless entry point.

### Session 2 — Syntax front end

Complete tokenisation, source locations, parsing, AST values, formatted diagnostics, and golden fixtures for the Milestone 1 language subset.

### Session 3 — Static semantics

Implement names, types, checked records and variants, exhaustiveness, domain quantities, typed core IR, and diagnostic goldens.

### Session 4 — Compiler and VM

Compile typed core into versioned bytecode. Implement deterministic bounded execution, runtime values, allocation budgets, and source-linked runtime faults.

### Session 5 — Headless tactical kernel

Build fixed ticks, entity state, observation gathering, intention collection, deterministic resolution, event emission, state hashing, and replay inputs without graphics.

### Session 6 — First end-to-end policy

Compile a simple policy, run it for several ticks in a fixture, emit a movement intention, resolve it, and prove deterministic replay and source provenance.

### Session 7 — pygame client

Only after the headless path is stable, add a window, snapshot renderer, bitmap font, camera, input-command adapter, and no authority leakage.

### Session 8 onward

Continue through perception, cover, projectiles, debugger queries, run comparison, and the Glasshouse vertical slice according to TODO.md.

## First proof policy

The first compiled program should remain deliberately small:

```text
policy cautious(view, memory) =
  match view.nearest_hostile with
  | Some(target) ->
      if target.distance < 8m then
        (memory, [SeekCover(target.position)])
      else
        (memory, [Advance(view.objective)])
  | None ->
      (memory, [Advance(view.objective)])
```

The exact surface syntax may evolve, but the proof must demonstrate:

- source spans;
- variant matching;
- a domain quantity;
- a conditional;
- explicit `(memory, intentions)` output;
- type checking;
- bytecode compilation;
- bounded VM execution;
- a source-linked intention.

## First causal proof

Create a deterministic fixture where an operative remains exposed because a danger threshold is too high. The trace must connect:

```text
source threshold literal
 -> comparison result
 -> advance branch
 -> Advance intention
 -> rejected cover opportunity or exposed movement
 -> projectile hit
 -> injury
```

Change only the threshold, rerun the same seed, and compare the two traces.

## Decisions Codex must not resolve silently

- changing Python or pygame-ce as the host stack;
- introducing Pymunk or another physics dependency into authority;
- using Python execution for the DSL;
- changing the no-direct-control rule;
- changing fixed-point or canonical-number policy;
- changing bytecode or save compatibility guarantees;
- dropping source-level provenance;
- broadening the MVP beyond the vertical slice;
- adding a copyleft or otherwise consequential bundled dependency;
- committing to multiplayer architecture.

## Expected early commands

The exact commands may differ after Milestone 0, but the repository should converge on equivalents of:

```bash
python -m pytest
python -m ruff check .
python -m ruff format --check .
python -m mypy src tests
python -m doctrine.cli doctor
python -m doctrine.cli compile examples/policies/cautious.dtr
python -m doctrine.cli simulate fixtures/minimal.json --ticks 120
```

## Common failure patterns

- Building the pygame client before the headless simulation.
- Treating the DSL as a parser-only feature without types or budgets.
- Storing floats in canonical state without a determinism policy.
- Recording strings instead of structured trace nodes and edges.
- Adding an ECS framework before entity requirements are understood.
- Implementing many tactical actions before one complete causal chain works.
- Building content editors before stable data schemas exist.
- Hiding simulation rules in rendering classes.
- Marking a milestone complete because code exists rather than because its exit criteria pass.
