# AGENTS.md

## Project intent

This repository implements Doctrine, a real-time physics-driven squad tactics game in LÖVE 2D. Players program squad behaviour using a small functional DSL, deploy the doctrine, watch autonomous missions execute, and inspect causal traces linking outcomes to code.

Read these files before making architectural changes:

1. `README.md`
2. `PRD.md`
3. `DSL_SPEC.md`
4. `ARCHITECTURE.md`
5. `SIMULATION_SPEC.md`
6. `CAUSAL_DEBUGGER.md`
7. `TODO.md`
8. `DECISIONS.md`

## Non-negotiable invariants

1. User programs do not directly mutate world state.
2. The DSL is pure at the language level and uses explicit memory.
3. The VM has no access to host Lua globals, filesystem, network, or wall-clock time.
4. The authoritative simulation uses fixed ticks.
5. Rendering cannot alter authoritative results.
6. Iteration order is explicit and deterministic.
7. Every player-visible program decision can be connected to source provenance.
8. Every intention has an explicit outcome or active state.
9. Program failure cannot crash the host application.
10. The first vertical slice remains the priority over campaign breadth.

## Implementation rules

- Prefer small modules with explicit inputs and outputs.
- Avoid global mutable state.
- Use stable integer IDs.
- Do not rely on Lua table iteration order.
- Use command buffers for structural simulation changes.
- Keep content data-driven and validated.
- Add serialization deliberately; do not dump arbitrary runtime tables.
- Keep simulation runnable headlessly.
- Treat replay format and bytecode format as versioned contracts.
- Do not add a dependency without documenting why and recording its licence.

## Task discipline

Before coding a task:

1. Identify the active milestone in `TODO.md`.
2. State the smallest coherent deliverable.
3. Identify affected invariants.
4. Add or update tests first where practical.
5. Implement the feature.
6. Run the full relevant test set.
7. Update documentation if public interfaces changed.

Do not start later milestones to avoid completing exit criteria in the current milestone.

## Definition of done

A task is done only when:

- implementation is complete;
- tests pass;
- deterministic behaviour is preserved;
- errors are structured;
- relevant events and provenance exist;
- headless mode remains functional;
- documentation is updated;
- no hidden direct-control shortcut undermines the product premise.

## Coding style

- Use descriptive module and function names.
- Keep functions short where it improves testability.
- Prefer immutable data flow at boundaries.
- Validate inputs at module boundaries.
- Return structured errors rather than throwing uncontrolled errors.
- Add comments for invariants and unusual ordering rules, not obvious syntax.

## Language-toolchain rules

- Preserve exact source spans from lexer through bytecode source maps.
- Never execute unverified bytecode.
- Keep instruction costs deterministic.
- Keep intrinsics pure and explicitly registered.
- Add golden tests for diagnostics and bytecode changes.
- Avoid advanced language features before the MVP subset is complete.

## Simulation rules

- System order is part of the contract.
- Randomness must use named deterministic streams.
- Physics callbacks should enqueue canonical contact records.
- No simulation code may read render delta time.
- State hashes must exclude presentation state.
- New components require serialization and hashing decisions.

## Causal-debugger rules

- Do not infer causes not recorded by provenance.
- Distinguish selected decision, emitted intention, and physical outcome.
- Show historical source associated with the deployed program version.
- Preserve upstream observation timestamps and source.
- Add regression fixtures for explanation bugs.

## Scope control

Reject or defer work on:

- multiplayer;
- procedural campaigns;
- large unit counts;
- general mod platform;
- unrestricted scripting;
- complex character customisation;
- extensive asset generation;
- polished base management;

until the vertical slice exit criteria are met.
