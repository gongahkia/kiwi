# Codex Handoff

## Continuing after the first prompt

Use a milestone-driven goal rather than an undifferentiated request to “finish the game.” The active agent should:

1. Read the documents relevant to the current milestone.
2. Inspect code and recent commits.
3. Select the first incomplete task.
4. Define its verification evidence.
5. Implement the smallest coherent slice.
6. Run focused and milestone checks.
7. Update GitHub issues and specifications; close an issue only with passing exit evidence.
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

Continue through perception, cover, projectiles, debugger queries, run comparison, and the Glasshouse vertical slice according to the GitHub issue milestones.

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
python -m kiwi.cli doctor
python -m kiwi.cli compile examples/policies/cautious.dtr
python -m kiwi.cli simulate fixtures/minimal.json --ticks 120
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
