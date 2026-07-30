# Codex Handoff

## Suggested first prompt

Use this prompt after placing these documents in the repository:

```text
Read README.md, PRD.md, DSL_SPEC.md, ARCHITECTURE.md, SIMULATION_SPEC.md,
CAUSAL_DEBUGGER.md, TODO.md, DECISIONS.md, and AGENTS.md.

We are implementing Doctrine, a LÖVE 2D real-time programmable squad tactics
game. The player writes a small pure functional DSL that consumes immutable
observations and explicit memory, returns new memory and typed intentions, and
never directly mutates the world. The simulation resolves intentions through
fixed-step physics and records causal provenance so battlefield outcomes can be
mapped back to exact source expressions.

Begin with Milestone 0 only. Inspect the existing repository before changing
anything. Propose the smallest coherent repository skeleton, test setup, stable
ID utility, deterministic PRNG wrapper, canonical serializer, and headless test
entry point. Do not implement gameplay, the DSL, or campaign systems yet.

Before editing, state:
1. the files you will create or change;
2. the invariants you will preserve;
3. the commands that will verify completion.

Then implement Milestone 0, run the tests, and update TODO.md with only tasks
that are genuinely complete. Do not mark an item complete without evidence.
```

## Recommended agent workflow

### Session 1

- Complete Milestone 0.
- Establish tests and headless execution.
- Do not create premature abstractions for ECS, parser, or UI.

### Session 2

- Implement lexer, spans, and parser skeleton.
- Add golden fixtures.
- Keep grammar deliberately small.

### Session 3

- Add resolver and type representation.
- Type-check only a narrow sample program.

### Session 4

- Define core IR and bytecode format.
- Implement verifier before broad VM support.

### Session 5

- Execute a pure `act` function headlessly.
- Return a typed `Wait` or `Move` intention.

### Session 6 onward

Follow `TODO.md` in order. Keep each change reviewable and runnable.

## First proof program

The first end-to-end DSL program should be intentionally trivial:

```text
act view memory =
  if view.self.health < 0.25
  then (memory, [Wait 500ms])
  else (memory, [Move view.assignment.destination Crouched])
```

The proof is complete when:

- source parses;
- types resolve;
- bytecode verifies;
- VM executes with bounded fuel;
- returned memory and intent serialize deterministically;
- source mapping identifies the selected branch;
- repeated execution produces identical outputs.

## Vertical-slice proof

Do not call the project viable merely because units move or the language compiles.

The decisive proof is:

1. Run the Glasshouse scenario with a flawed doctrine.
2. A medic or support operative makes a poor decision.
3. The debugger identifies the observation, priority rule, selected branch, and physical consequence.
4. Edit a small functional expression.
5. Recompile.
6. Rerun with the same seed and initial state.
7. Show the first divergent decision and a materially different outcome.

## Questions the agent should not resolve silently

Document a decision before changing any of these:

- authoritative system order;
- state-hash schema;
- bytecode format;
- replay format;
- public DSL syntax;
- memory migration semantics;
- deterministic physics guarantees;
- permanent-death rules;
- third-party dependency choices.

## Expected early commands

Exact commands may differ, but the repository should converge on a small set such as:

```text
make run
make test
make check
make headless FIXTURE=tests/fixtures/minimal_mission.json
make replay FILE=tests/fixtures/minimal.replay
```

## Anti-patterns

Do not:

- embed player scripts with `loadstring` or unrestricted Lua evaluation;
- put simulation logic in `love.draw`;
- use wall-clock time for authoritative decisions;
- use unordered tables for canonical iteration;
- build a complete editor before a headless language pipeline works;
- build campaign content before causal tracing works;
- hide failed intents without explicit outcome records;
- replace provenance with generic log strings;
- add direct unit control as a temporary shortcut.
