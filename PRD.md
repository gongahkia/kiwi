# Product Requirements Document

## 1. Product summary

**Working title:** Doctrine  
**Genre:** Real-time programmable squad tactics / simulation strategy  
**Engine:** LÖVE 2D  
**Primary platform:** Desktop  
**Primary audience:** Players who enjoy tactical systems, programming games, automation, simulation, debugging, and emergent outcomes

Doctrine is a squad tactics game inspired structurally by XCOM-style mission preparation and persistent operatives, but it replaces direct tactical commands with a functional DSL. Players prepare doctrine programs before deployment, run missions in real time, and inspect causal traces that map battlefield consequences to the code and observations that produced them.

The game should feel like operating a tactical software laboratory rather than issuing conventional turn-based commands.

## 2. Product thesis

Conventional tactics games ask the player to choose the best action at each moment. Doctrine asks the player to design a system that can repeatedly choose good actions under incomplete information, physical uncertainty, communication delays, and changing conditions.

The project is valuable if all three statements are true:

1. Writing or modifying doctrine is understandable without requiring professional programming experience.
2. Watching the squad execute is tense and legible rather than passive.
3. Failures are sufficiently explainable that revising the code feels rational rather than speculative.

## 3. Product promise

> Program the doctrine. Deploy the squad. Debug the consequences.

Every major feature must reinforce at least one part of this promise.

## 4. Goals

### 4.1 Product goals

- Make programming the primary form of tactical control.
- Provide a small functional language with a low initial cognitive load and high compositional depth.
- Produce physically simulated tactical outcomes rather than resolving attacks through hidden percentages alone.
- Create a causal debugger that connects observable consequences to source code, observations, internal state, and physical events.
- Support persistent operatives, equipment, injuries, and squad history.
- Allow missions to be replayed deterministically for testing and post-mission analysis.
- Make the first meaningful experience achievable with short programs and strong standard-library support.

### 4.2 Portfolio and engineering goals

The project should demonstrate:

- language design;
- parsing and type checking;
- compilation or transpilation to a custom intermediate representation;
- deterministic virtual-machine execution;
- real-time physics integration;
- event sourcing and replay;
- causal provenance tracking;
- spatial simulation and AI;
- editor and debugger tooling;
- testable simulation architecture;
- data-driven content.

### 4.3 Adoption goals

The project should eventually support:

- shareable doctrines;
- challenge scenarios;
- deterministic score comparison;
- community-authored missions;
- downloadable squad templates;
- headless tournament or benchmark execution.

These are post-MVP goals and must not delay the vertical slice.

## 5. Non-goals

The MVP is not:

- a complete XCOM clone;
- a general-purpose programming IDE;
- a universal physics engine;
- a competitive multiplayer game;
- a large procedural campaign;
- an unrestricted Lua sandbox;
- a block-programming tutorial;
- a direct-control action game;
- a simulation of every physiological or ballistic variable;
- a content-heavy tactics game with many factions and hundreds of weapons.

## 6. Core player experience

The intended emotional rhythm is:

1. **Uncertainty** — the briefing provides incomplete intelligence.
2. **Preparation** — the player selects operatives, equipment, and doctrine modules.
3. **Confidence** — the program compiles and appears logically sound.
4. **Tension** — the squad executes autonomously in real time.
5. **Surprise** — physical and informational interactions produce an unanticipated outcome.
6. **Investigation** — the player examines traces, timelines, and code provenance.
7. **Understanding** — the player identifies a flawed assumption or rule.
8. **Iteration** — the player modifies and tests the doctrine.
9. **Mastery** — the squad becomes robust across a wider range of situations.

## 7. Core gameplay loop

### 7.1 Mission briefing

The player receives:

- objective and failure conditions;
- partial map information;
- probable threats;
- environmental constraints;
- extraction rules;
- available deployment slots;
- expected communication conditions.

### 7.2 Squad assembly

The player selects:

- persistent operatives;
- weapons and tools;
- armour and mobility equipment;
- sensor and communication modules;
- a squad doctrine;
- operative-specific policies;
- fallback and extraction behaviour.

### 7.3 Programming

The player edits functional programs through an integrated editor.

The initial experience should centre on:

- changing constants;
- choosing standard-library functions;
- composing priority rules;
- handling optional observations;
- matching mission events;
- selecting fallback behaviour.

### 7.4 Compilation and validation

The compiler checks:

- syntax;
- inferred and declared types;
- units and dimensions;
- exhaustive pattern matching;
- capability availability;
- instruction budgets;
- recursive cycles;
- invalid references;
- unsafe deployment assumptions.

Warnings should be actionable and explain likely battlefield effects.

### 7.5 Execution

The mission runs in real time.

Each operative repeatedly:

1. receives an immutable observation;
2. evaluates its policy with prior memory;
3. returns new memory and one or more intentions;
4. has those intentions resolved through the simulation;
5. receives events and consequences on later ticks.

### 7.6 Tactical signals

The player may issue a deliberately limited set of high-level signals during missions:

- advance to region;
- hold region;
- prioritise objective;
- extract at location;
- abort mission.

Signals are inputs to doctrine. They never directly move, aim, fire, heal, or override an operative.

### 7.7 Post-mission analysis

The player can:

- replay the mission;
- inspect an operative timeline;
- click an outcome and view its causal chain;
- jump from an event to the responsible source expression;
- inspect the observations available at decision time;
- compare intended and actual outcomes;
- branch from a recorded state in a testing sandbox;
- revise doctrine and rerun.

## 8. Functional requirements

### 8.1 Mission simulation

- Fixed-step simulation independent of rendering frame rate.
- Physical projectiles with travel time and collision.
- Cover geometry that affects line of sight, impact, and destruction.
- Operative movement with acceleration, stance, collision, and path constraints.
- Damage, incapacitation, stabilisation, and extraction.
- Suppression or pressure represented as explicit observable state.
- Incomplete and delayed perception.
- Communication range, latency, and interruption.
- Deterministic random streams scoped by system and entity.

### 8.2 DSL

- Pure functional semantics at the language level.
- Explicit memory threading.
- Tagged unions and exhaustive pattern matching.
- Lists, records, options, results, and bounded folds.
- No unrestricted mutation.
- No direct access to Lua globals, filesystem, network, wall-clock time, or host process.
- Typed intentions instead of direct world mutation.
- Type-directed editor assistance.
- Stable bytecode or IR versioning.
- Source mapping from bytecode instructions to source spans.

### 8.3 Causal debugger

- Event timeline per operative and squad.
- Trace entries with source span, function, inputs, output, and cost.
- Provenance links between observations, evaluations, intentions, physical resolution, and consequences.
- Ability to answer “why did this operative do this?”
- Ability to answer “why did this intention fail?”
- Ability to answer “why was another action not chosen?” for priority-based decisions.
- Replay navigation and deterministic state restoration.

### 8.4 Workbench

- Source editor.
- Compiler diagnostics.
- Program deployment configuration.
- Scenario test harness.
- Watch expressions and probes.
- Timeline and trace inspector.
- Mission telemetry overlays.
- Version history and rollback.

### 8.5 Persistent campaign

Post-vertical-slice requirements:

- named operatives;
- equipment inventory;
- injuries and recovery;
- mission history;
- experience unlocks that grant capabilities or standard-library modules rather than arbitrary numerical bonuses;
- doctrine versions associated with mission records;
- squad roster and deployment management.

## 9. User stories

### New player

- As a new player, I can complete the first mission by changing only a few provided expressions.
- As a new player, compiler errors tell me what happened and how to correct it.
- As a new player, I can understand why an operative chose an action.
- As a new player, I am not presented with the entire language or standard library at once.

### Intermediate player

- As an intermediate player, I can create reusable functions and role policies.
- As an intermediate player, I can coordinate operatives through typed messages.
- As an intermediate player, I can test a doctrine against recorded mission states.
- As an intermediate player, I can compare two doctrine versions against the same deterministic scenario.

### Advanced player

- As an advanced player, I can replace default targeting, cover, or formation algorithms.
- As an advanced player, I can inspect instruction costs and optimise hot paths.
- As an advanced player, I can author doctrine libraries and challenge scenarios.
- As an advanced player, I can run headless simulations for benchmarking.

## 10. MVP scope

The MVP consists of a single polished vertical slice.

### 10.1 Scenario

A compact urban or industrial map with:

- four player operatives;
- two hostile operatives or drones;
- one rescue or retrieval objective;
- one extraction zone;
- destructible waist-high and full-height cover;
- one environmental hazard;
- partial fog of war.

### 10.2 Player capabilities

- Choose from two equipment configurations.
- Edit one squad doctrine and one operative policy template.
- Compile and deploy before the mission.
- Issue `AdvanceTo`, `Hold`, and `ExtractAt` signals.
- Watch the mission run.
- Pause only in analysis mode after the run, not during the canonical run.
- Inspect one complete causal chain.
- Modify doctrine and rerun from the same seed.

### 10.3 DSL subset

- integers, floats, booleans, strings, durations, distances, positions;
- records;
- tagged unions;
- `Option` and `Result`;
- functions;
- `let`;
- `if`;
- `case`;
- lists;
- pipelines;
- bounded `map`, `filter`, `fold`, and `firstApplicable`;
- explicit memory;
- typed intentions;
- no user recursion in the MVP.

### 10.4 Debugger subset

- source-level trace for each policy evaluation;
- selected-action explanation;
- rejected-candidate explanation;
- observation snapshot at decision time;
- intention-to-outcome trace;
- deterministic replay scrubber;
- source highlighting.

## 11. Success metrics

The vertical slice is successful when internal testers can:

- identify the cause of a failed tactical decision without reading engine code;
- modify doctrine and reliably produce a different outcome;
- explain the distinction between a program intention and the physical result;
- complete the scenario without writing a full program from a blank file;
- understand at least one functional concept through play;
- replay the same seed with identical authoritative simulation hashes.

Quantitative development targets:

- 100% deterministic replay match on supported test platforms for the same build and configuration;
- compiler diagnostics map to accurate source spans;
- no host-language exception can escape from user program execution;
- a standard four-versus-two mission remains within the target frame budget;
- trace collection can be disabled or sampled for performance comparisons;
- the first scenario can be completed using fewer than approximately 40 lines of player-visible DSL.

## 12. Risks and mitigations

### Risk: Programming is too intimidating

Mitigation:

- start from templates;
- reveal language features gradually;
- use type-directed completion;
- make standard-library functions tactically meaningful;
- provide immediate scenario tests;
- show code and behaviour side by side.

### Risk: Watching is boring

Mitigation:

- maintain real-time pressure;
- allow limited high-level signals;
- keep missions short;
- make physical outcomes readable;
- use strong anticipation and telemetry;
- ensure doctrine decisions occur frequently enough to observe.

### Risk: Failures feel arbitrary

Mitigation:

- record exact observations and timestamps;
- distinguish unknown information from poor decisions;
- expose random rolls where randomness exists;
- provide counterfactual and rejected-action explanations;
- make communication delay visible.

### Risk: Determinism conflicts with physics

Mitigation:

- use a fixed timestep;
- pin engine and runtime versions;
- control iteration ordering;
- use deterministic random streams;
- avoid dependence on table iteration order;
- store authoritative snapshots and hashes;
- initially guarantee determinism only for the same build and supported environment.

### Risk: Scope expands into a complete tactical simulator

Mitigation:

- retain one scenario until the full code-to-consequence loop is proven;
- add systems only when they create new programmable decisions;
- reject content whose primary value is cosmetic variety.

## 13. Release stages

### Prototype

Proves:

- DSL evaluation;
- intention emission;
- autonomous agents;
- simple physical outcome;
- trace back to source.

### Vertical slice

Proves the complete user experience with one mission.

### Alpha

Adds:

- persistent roster;
- several mission archetypes;
- richer standard library;
- doctrine versioning;
- campaign progression.

### Beta

Adds:

- content authoring tools;
- doctrine sharing;
- performance optimisation;
- accessibility and onboarding polish.

### 1.0 candidate

Requires:

- a coherent short campaign;
- stable save and replay formats;
- strong diagnostics;
- robust mod or challenge packaging;
- production-ready content pipeline.
