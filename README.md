# Doctrine — Python Project Documentation

> Working title. Rename freely before public release.

Doctrine is a real-time, physics-aware squad tactics game in which the player does not directly command individual operatives. The player writes a small functional program that turns incomplete observations into tactical intentions. A mission then runs in real time, and an integrated causal debugger explains how battlefield consequences arose from specific expressions, data, decisions, and physical events.

The project is implemented in Python. `pygame-ce` provides the desktop application shell, rendering, input, audio, and bitmap-font presentation. The authoritative simulation, functional language toolchain, deterministic virtual machine, replay system, and causal-debugger model are project-owned Python modules and must run headlessly.

The player-facing language is **not Python**. It is a separate functional DSL with its own syntax, type system, compiler, bytecode, runtime limits, source maps, and versioning. Python is the implementation language because it supports rapid iteration on compiler architecture, simulation models, diagnostic tooling, trace analysis, and automated testing.

## Product promise

**Program the doctrine. Deploy the squad. Debug the consequences.**

The defining loop is:

1. Receive an incomplete mission briefing.
2. Select and equip a persistent squad.
3. Edit squad and operative policies in the in-game workbench.
4. Compile and validate those policies.
5. Run the mission in real time with only limited high-level signals.
6. Inspect a causal trace linking outcomes back to code and observed data.
7. Revise the doctrine and rerun or continue the campaign.

## Non-negotiable pillars

1. **Autonomous execution** — no ordinary select-and-right-click control.
2. **Functional programming** — user programs are pure transformations over immutable observations and explicit memory.
3. **Intent, not mutation** — programs request actions; the simulation resolves outcomes.
4. **Deterministic authority** — identical inputs, build, seed, and content produce identical state hashes.
5. **Causal legibility** — important outcomes can be traced back to program evaluations and world events.
6. **Small language core** — complexity is introduced through composition and libraries rather than dozens of primitive commands.
7. **Headless-first engineering** — the compiler, VM, simulation, replay, and explanation engine do not depend on pygame.

## Host stack

- Python 3.12 or later
- pygame-ce for rendering, input, audio, and window management
- project-owned fixed-step simulation
- project-owned functional DSL compiler and VM
- pytest for testing
- Hypothesis for property tests once the foundational representations stabilise
- Ruff for formatting and linting
- static type checking with mypy or Pyright, selected and pinned during Milestone 0

Pymunk, Box2D, or another external physics engine is **not** part of the MVP authority. It may later be used for non-authoritative debris or isolated experiments only after deterministic requirements are measured and documented.

## Documentation map

- `PRD.md` — product requirements, scope, users, risks, success criteria, and vertical slice.
- `GAME_DESIGN.md` — mission structure, player agency, operatives, combat, information, progression, and first scenario.
- `DSL_SPEC.md` — functional language semantics, syntax, type system, compiler, bytecode, VM, and diagnostics.
- `LANGUAGE_ROADMAP.md` — how the DSL can grow without invalidating the small-core design.
- `ARCHITECTURE.md` — repository layout, module boundaries, dependency rules, runtime pipeline, and performance budgets.
- `PYTHON_STACK.md` — Python, pygame-ce, dependency, performance, and packaging guidance.
- `SIMULATION_SPEC.md` — deterministic time, entities, observations, intentions, movement, projectiles, cover, damage, and hashing.
- `CAUSAL_DEBUGGER.md` — provenance model, trace levels, source linkage, queries, retention, and UI contract.
- `UX_UI.md` — workbench, terminal, mission view, debugger, controls, accessibility, and bitmap-font direction.
- `DATA_FORMATS.md` — source, bytecode, mission, replay, trace, save, and schema-versioning rules.
- `TESTING.md` — test layers, determinism harnesses, compiler goldens, properties, performance, and CI.
- `DECISIONS.md` — settled decisions, prohibited shortcuts, open decisions, and change process.
- `TODO.md` — gated implementation milestones and concrete exit criteria.
- `AGENTS.md` — rules for Codex and other repository agents.
- `CODEX_HANDOFF.md` — exact initial prompt and recommended implementation workflow.

## Recommended reading order

1. `AGENTS.md`
2. `PRD.md`
3. `DECISIONS.md`
4. `ARCHITECTURE.md`
5. `DSL_SPEC.md`
6. `SIMULATION_SPEC.md`
7. `CAUSAL_DEBUGGER.md`
8. `TODO.md`
9. The specification relevant to the active milestone

## First technical proof

Before building a polished editor, campaign, or content pipeline, prove this chain headlessly:

```text
DSL source
  -> parsed AST with source spans
  -> typed core IR
  -> deterministic bytecode
  -> bounded VM evaluation
  -> emitted tactical intention
  -> deterministic simulation resolution
  -> causal event linked to the source expression
  -> replay with matching state hashes
```

The first playable proof must then demonstrate:

1. A squad fails because of a flawed policy.
2. The debugger identifies the decisive expression and evidence.
3. The player edits the function.
4. The compiler accepts the revision.
5. The same scenario and seed rerun deterministically.
6. The changed code produces a materially different tactical outcome.

If that loop is not satisfying, more missions, factions, graphics, and language features will not fix the project.
