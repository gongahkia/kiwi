# Doctrine — Project Documentation

> Working title. Rename freely before implementation.

Doctrine is a real-time, physics-driven squad tactics game in which the player does not directly control operatives. Instead, the player writes and deploys a small functional domain-specific language (DSL) that determines how a persistent squad observes, reasons, communicates, moves, fights, rescues, retreats, and completes mission objectives.

The central loop is:

> **Program the doctrine. Deploy the squad. Debug the consequences.**

This repository packet is intended to transfer the complete project context to a local coding agent. It defines the product, implementation architecture, DSL, deterministic simulation model, causal debugger, UI, testing approach, and delivery plan.

## Core pillars

1. **Code is command** — there is no unrestricted click-to-move or click-to-shoot control.
2. **Intent is not outcome** — programs emit intentions; the physical simulation resolves what actually happens.
3. **Consequences are explainable** — every important outcome can be traced to observations, data, functions, rules, and physical events.
4. **The language is small** — the surface DSL is approachable and compiles into a tiny deterministic functional core.
5. **Tactics emerge from composition** — cover, suppression, target selection, rescue, and formation behaviour are library functions, not primitive engine cheats.
6. **Squads persist** — injuries, equipment, experience, and mission history matter across operations.
7. **Real time creates pressure** — deployment, communication, and physical events continue while programs run.

## Documentation map

- [`PRD.md`](PRD.md) — product requirements, goals, scope, user stories, and acceptance criteria.
- [`GAME_DESIGN.md`](GAME_DESIGN.md) — campaign, missions, squad systems, progression, and gameplay rules.
- [`DSL_SPEC.md`](DSL_SPEC.md) — functional DSL semantics, syntax, types, standard library, compiler, and VM.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — runtime modules, boundaries, data flow, repository structure, and implementation constraints.
- [`SIMULATION_SPEC.md`](SIMULATION_SPEC.md) — fixed-step physics, intents, observations, determinism, damage, cover, and replay.
- [`CAUSAL_DEBUGGER.md`](CAUSAL_DEBUGGER.md) — trace model, provenance graph, explanations, time travel, and code-to-consequence mapping.
- [`UX_UI.md`](UX_UI.md) — workbench, mission interface, terminal, editor, telemetry, and accessibility.
- [`TESTING.md`](TESTING.md) — unit, property, determinism, simulation, golden, fuzz, and content tests.
- [`TODO.md`](TODO.md) — phased implementation plan with concrete deliverables and exit criteria.
- [`DECISIONS.md`](DECISIONS.md) — settled decisions, unresolved questions, and explicit non-goals.
- [`AGENTS.md`](AGENTS.md) — operating instructions for Codex and other coding agents.
- [`CODEX_HANDOFF.md`](CODEX_HANDOFF.md) — first-session prompt and recommended implementation sequence.

## Recommended starting point

Do not begin with campaign systems, procedural content, networking, or a complete language.

Build the vertical slice described in `TODO.md`:

- one small map;
- four operatives;
- one hostile archetype;
- physical projectiles and destructible cover;
- a minimal functional DSL;
- compilation into deterministic bytecode;
- pre-mission deployment;
- autonomous execution;
- replay;
- a causal trace that highlights which function and condition produced a failed decision.

The first success criterion is not “the RTS works.” It is:

> A player can observe a squad failure, identify the responsible program decision, modify the code, rerun the same scenario deterministically, and observe a materially different result.

## Development

Milestone 0 targets LÖVE 11.5 with LuaJIT 2.1 (Lua 5.1 semantics). There are no runtime dependencies. The local test framework in `tests/test.lua` is dependency-free; StyLua 2.5.2 (MIT) is the development formatter and lint checker.

```text
make run       # launch the minimal LÖVE shell
make test      # run unit tests without LÖVE
make headless  # run the headless utility smoke entry point
make check     # lint, test, headless smoke, and content skeleton validation
make smoke     # launch then immediately quit the LÖVE shell
```

Canonical serialization is format version 1. It emits string-keyed maps in sorted key order and contiguous positive-integer tables as arrays; empty tables serialize as maps. Hashes use FNV-1a 32 over that representation.
