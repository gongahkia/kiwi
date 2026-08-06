# Product Requirements Document

## 1. Product summary

Kiwi is a single-player real-time squad tactics game in which the player programs the decision logic of a persistent tactical squad using a deliberately small functional language. Missions execute autonomously under incomplete information. Rather than directly moving and firing each operative, the player defines how the squad observes, prioritises, communicates, chooses cover, handles casualties, and pursues objectives.

The product’s distinguishing feature is a causal debugger that maps battlefield outcomes back to program evaluations. When an operative is exposed, misses an extraction window, fires on a low-priority target, or fails to aid an ally, the player can inspect the observation data, function calls, branch choices, emitted intentions, arbitration decisions, and physical events that produced the result.

The first release target is a desktop vertical slice implemented in Python with pygame-ce. The player-facing functional DSL is compiled to a project-owned deterministic bytecode VM. The authoritative simulation runs headlessly and is independent of the renderer. The Terminal lab presents generated pixel-diorama assets through a rotatable isometric camera, while retaining the same snapshot-only presentation boundary.

## 2. Product thesis

Programming games frequently reduce code to automation puzzles, while tactics games usually reserve all meaningful decisions for direct player input. Kiwi combines the two:

- Tactical decisions remain meaningful because missions unfold with cover, projectiles, uncertainty, timing, suppression, injury, and extraction pressure.
- Programming remains meaningful because code controls actual autonomous behaviour rather than cosmetic automation.
- Failure remains learnable because consequences are traceable to source code and evidence.
- Repetition remains purposeful because deterministic reruns allow controlled experiments.

The player is not writing scripts alongside the game. **Writing, deploying, and debugging kiwi is the game.**

## 3. Product promise

> Program the kiwi. Deploy the squad. Debug the consequences.

The player should regularly experience:

- predicting how a policy will behave;
- watching the prediction fail for a specific reason;
- understanding the causal chain rather than blaming opaque AI;
- changing one function or value;
- rerunning the same situation;
- observing a materially improved or newly broken outcome.

## 4. Target users

### 4.1 Primary users

- Programmers who enjoy tactical and systems games.
- Players interested in automation, simulation, debugging, and emergent behaviour.
- Students or professionals curious about functional programming but not seeking a formal teaching product.
- Players who enjoy XCOM-like squad persistence but want a less conventional control model.

### 4.2 Secondary users

- Strategy players willing to use templates and type-directed editing rather than authoring large programs.
- Developers interested in the compiler, VM, replay, or causal-trace implementation.
- Challenge creators who may later share policies, fixtures, or mission configurations.

### 4.3 Not initially targeted

- Players seeking action controls or conventional turn-based tactics.
- Players unwilling to read or modify textual logic.
- Competitive multiplayer audiences.
- Users seeking a general-purpose programming environment.

## 5. Product goals

### 5.1 Core gameplay goals

- Make policy design produce visible tactical consequences.
- Keep the beginner language surface small enough to edit within minutes.
- Support advanced composition without exposing unrestricted complexity.
- Make autonomous execution tense rather than passive.
- Provide enough player influence during missions through typed strategic signals without restoring micromanagement.
- Make major failures explainable through the causal debugger.

### 5.2 Engineering goals

- Build an independent functional language front end and VM.
- Maintain deterministic headless simulation and replay verification.
- Preserve source spans and provenance end to end.
- Keep authoritative state independent of pygame and wall-clock timing.
- Support golden, property, replay, and causal-query testing.
- Make content and run formats explicitly versioned.

### 5.3 Portfolio goals

The project should demonstrate:

- language and compiler design;
- type systems and diagnostics;
- deterministic virtual-machine execution;
- fixed-step simulation;
- tactical geometry and information modelling;
- event sourcing and replay;
- causal provenance and explanation tooling;
- custom in-game editor and bitmap UI;
- disciplined testing of nontrivial interactive systems.

### 5.4 Adoption goals

The vertical slice should be understandable from a short video or animated demonstration:

1. Show the policy.
2. Show the squad make a poor decision.
3. Click the consequence.
4. Highlight the responsible code and data.
5. Change the code.
6. Replay the same situation.
7. Show the changed result.

This loop is the project’s strongest public-facing hook.

## 6. Non-goals

The MVP does not attempt to provide:

- a broad campaign;
- multiplayer;
- procedural campaigns or open-world generation;
- complex base building;
- general rigid-body physics;
- mod scripting through Python;
- a universal IDE;
- many factions or enemy families;
- cinematic narrative production;
- a large item economy;
- live-service infrastructure;
- machine-learning agents;
- an unrestricted or academically complete functional language.

## 7. Core player experience

The player acts at three timescales.

### 7.1 Before a mission

The player:

- reads the mission briefing;
- reviews uncertain intelligence;
- selects a small persistent squad;
- chooses equipment and capabilities;
- edits squad kiwi and operative policies;
- compiles and reviews errors or warnings;
- runs bounded training or fixture tests where available;
- deploys the compiled policy bundle.

### 7.2 During a mission

The player:

- watches real-time execution;
- inspects sensor, communication, cover, target, and intention overlays;
- changes only permitted high-level typed signals;
- may adjust simulation speed where the mode permits;
- bookmarks important events;
- does not directly command individual actions.

Potential high-level signals include:

```text
AdvanceTo(region)
Hold(region)
Prioritise(objective)
Avoid(region)
ExtractAt(position)
Abort
```

A signal is data supplied to kiwi. It does not bypass kiwi.

### 7.3 After or between runs

The player:

- opens the mission timeline;
- selects an outcome such as injury, missed shot, stalled movement, or failed objective;
- asks why it happened;
- follows the causal chain into policy source;
- compares the run with a previous version;
- edits the policy and reruns a fixture or mission.

## 8. Core gameplay loop

### 8.1 Brief

Present objectives, constraints, probable threats, extraction conditions, and uncertain intelligence. Never reveal omniscient truth unless the scenario explicitly grants it.

### 8.2 Configure

Select operatives, equipment, policy modules, initial parameters, and squad-level kiwi.

### 8.3 Program

Edit functions through templates, typed completions, inline documentation, source diagnostics, and small example fixtures.

### 8.4 Compile

Run the full language pipeline:

```text
source -> tokens -> syntax tree -> name resolution -> typed tree
       -> capability and budget checks -> core IR -> bytecode -> source map
```

### 8.5 Execute

Run the mission with fixed-step authority. Each policy receives an immutable observation and explicit memory, returning new memory and intentions.

### 8.6 Resolve

Validate and arbitrate intentions, then resolve movement, aiming, projectiles, cover, damage, communication, and objectives.

### 8.7 Explain

Build structured provenance from source evaluation through tactical consequence.

### 8.8 Revise

Modify the kiwi and rerun under controlled inputs.

### 8.9 Challenge lab

The local lab offers deterministic Daily and Practice contracts. A Daily contract is selected by an application-supplied ISO calendar-date string; a Practice contract is selected by an explicit seed. Both use versioned modular 32×32 districts and deterministic escalation. Each completed attempt shows tactical outcomes alongside code-cost metrics and local histograms without a composite score, network submission, or leaderboard.

## 9. Functional requirements

### 9.1 Functional DSL

The system must provide:

- lexer and parser with source spans;
- immutable AST;
- named functions and local bindings;
- conditionals and exhaustive pattern matching;
- records, lists, and algebraic variants;
- checked primitive and tactical domain types;
- explicit memory threading;
- bounded standard-library combinators;
- typed observation, signal, and intention APIs;
- stable diagnostic codes;
- source formatting or at least stable pretty printing;
- versioned bytecode and source maps;
- deterministic instruction and allocation budgets;
- structured runtime faults and fallback behaviour.

### 9.2 Tactical simulation

The system must provide:

- fixed integer ticks;
- deterministic ordering and seeded random streams;
- small-squad entity state;
- discrete or fixed-point positions and velocities;
- obstacles and cover edges;
- visibility and uncertain contacts;
- typed communication with delay and loss where configured;
- movement intentions and path queries;
- aiming, firing, physical projectile travel, impact, and damage;
- suppression and basic medical stabilisation;
- mission objectives and extraction;
- state hashing, snapshots, and replay.

### 9.3 Causal debugger

The system must provide:

- source-linked evaluation records;
- observation-field read provenance;
- branch and pattern-selection provenance;
- intention origin and priority;
- validation and arbitration outcomes;
- world-event links;
- major consequence links;
- “why selected?”, “why not?”, and “why failed?” queries;
- timeline navigation;
- source highlighting;
- deterministic comparison between two runs;
- configurable trace detail and retention.

### 9.4 Workbench

The system must provide:

- bitmap-font source editor;
- syntax colouring;
- line and column display;
- diagnostics list and inline markers;
- type or documentation hints;
- compile command;
- policy and fixture selection;
- source-to-trace navigation;
- basic keyboard-first controls;
- copy and paste through platform APIs;
- readable scaling at integer and high-DPI window sizes.

The MVP editor need not provide general IDE features such as multi-cursor editing, language-server protocols, plugins, or arbitrary project management.

### 9.5 Mission presentation

The graphical client must provide:

- map and operative rendering;
- camera movement and zoom;
- objective and extraction markers;
- visible projectiles and impacts;
- cover and visibility overlays;
- current policy version and high-level signal state;
- event timeline markers;
- selectable entities and events for inspection without direct command authority.
- a rotatable isometric tactical presentation using an original texture atlas, fixed-tick animation, and event-driven local audio;
- bidirectional source and entity selection that seeks retained trace evidence without re-running authority;
- presentation themes that apply to the editor, tactical view, and local result page.

### 9.6 Persistence

The system must store:

- source policies;
- compiled policy metadata;
- missions and fixtures;
- replay inputs and state hashes;
- trace files or trace references;
- user settings;
- later, campaign and operative state.

All durable formats require schema versions and validation.

## 10. User stories

### 10.1 New player

- As a new player, I can start from a working policy template rather than a blank file.
- I can change one threshold and understand its type and effect.
- The compiler tells me exactly where and why a program is invalid.
- When the squad fails, I can click the failure and see the relevant line of code.

### 10.2 Intermediate player

- I can compose reusable tactical functions.
- I can define role-specific behaviour.
- I can account for missing or stale observations through explicit variants.
- I can compare two policy versions against the same scenario and seed.

### 10.3 Advanced player

- I can define custom records and variants within supported limits.
- I can replace standard target, cover, and coordination functions.
- I can reason about instruction budgets and communication delays.
- I can inspect lower-level evaluation and resolution traces.

## 11. MVP vertical slice

### 11.1 Scenario: Terminal

A four-operative squad enters a small office or research structure to retrieve a protected objective and extract. The map includes:

- two approaches;
- several cover edges;
- one breachable or alternate entry;
- incomplete hostile intelligence;
- one timed lockdown;
- an extraction zone;
- a casualty risk created by an intentionally flawed policy.

The bundled scout policy treats a contact uncertainty radius at or below one metre as sufficient reason to advance without inspecting cover. Its deterministic causal fixture traces that advance through hostile fire, projectile impact, and injury.

### 11.2 Required player actions

The player must be able to:

- inspect the briefing;
- load the provided policy;
- compile it;
- run the mission;
- select the injury event;
- trace the event to a source comparison or priority function;
- change a value or function;
- rerun the same mission and seed;
- observe changed behaviour;
- compare the two causal chains.

### 11.3 Required language subset

- integer, boolean, string, duration, distance, probability, position;
- functions and application;
- `let`;
- `if`;
- records and field access;
- `Option`-like variants;
- pattern matching;
- lists with bounded `map`, `filter`, `fold`, and selection functions;
- explicit memory record;
- observation access;
- `Move`, `TakeCover`, `Aim`, `Fire`, `Stabilise`, `Emit`, and `Wait` intentions;
- no user recursion.

### 11.4 Required debugger subset

- trace selected source span;
- show relevant observation values;
- show selected branch;
- show emitted intention;
- show validation and resolution outcome;
- show projectile impact and injury;
- compare changed branch and consequence between two runs.

### 11.5 Required presentation subset

- workbench screen;
- tactical map;
- four operatives and a small enemy force;
- cover and visibility overlays;
- projectile rendering;
- timeline and source pane;
- bitmap terminal font;
- deterministic headless and graphical execution of the same mission.

## 12. Success criteria

### 12.1 Prototype success

The project passes the first technical proof when one source expression can be compiled, executed, resolved into a world change, traced to a consequence, and deterministically replayed.

### 12.2 Vertical-slice success

The vertical slice succeeds when an unfamiliar programmer can:

- understand the mission objective;
- identify why the provided policy failed;
- make a plausible correction;
- observe a changed outcome;
- explain the code-to-consequence relationship.

### 12.3 Engineering success

- All authoritative tests run headlessly.
- Repeated fixture runs produce matching hashes.
- Compiler and runtime errors contain no leaked Python stack traces in normal use.
- Presentation code cannot mutate authoritative state.
- Trace queries are validated against known causal fixtures.
- Performance remains interactive on a typical modern laptop for the target squad and map size.

## 13. Risks and mitigations

### Risk: The language overwhelms players

Mitigations:

- working templates;
- one new construct per tutorial;
- type-directed completions;
- limited visible standard library;
- domain-specific examples;
- no blank-file onboarding;
- progressively unlocked advanced syntax.

### Risk: Watching autonomous execution becomes passive

Mitigations:

- incomplete intelligence;
- limited high-level signals;
- meaningful time pressure;
- visible predictions and uncertainty;
- short, dense missions;
- tactical overlays and event bookmarks;
- later, carefully bounded deployment windows.

### Risk: Outcomes feel arbitrary

Mitigations:

- deterministic reruns;
- structured causal traces;
- visible physical projectiles;
- explicit uncertainty values;
- named random streams and recorded draws;
- explanation queries;
- counterfactual comparison where supportable.

### Risk: Python performance limits the simulation

Mitigations:

- target a small squad and compact maps;
- use immutable snapshots selectively rather than cloning all state each frame;
- use slotted data structures and integer representations;
- profile before optimising;
- batch geometry queries;
- isolate hot loops for optional later native acceleration without changing semantics.

### Risk: DSL scope becomes a language-research project

Mitigations:

- milestone-gated feature set;
- separate language roadmap;
- no recursion or advanced polymorphism in MVP;
- every language feature must unlock a concrete gameplay use;
- standard library before new syntax.

### Risk: Causal traces become too large

Mitigations:

- trace levels;
- bounded retention windows;
- event summarisation;
- source-span and value interning;
- checkpointed replay with on-demand re-execution;
- performance budgets and trace-size tests.

### Risk: External physics breaks determinism

Mitigation: project-owned authoritative simulation for MVP. External physics remains non-authoritative unless a documented deterministic contract is proven.

## 14. Release stages

### Stage 0 — Technical chain

Compiler, VM, one intention, one simulation consequence, one causal path, one replay.

### Stage 1 — Headless tactical prototype

Movement, perception, cover, firing, injury, mission objective, deterministic CLI.

### Stage 2 — Workbench and tactical viewer

pygame client, bitmap editor, overlays, timeline, source navigation.

### Stage 3 — Terminal vertical slice

Complete playable loop and run comparison.

### Stage 4 — Alpha foundation

Persistent squad state, several policies and enemy behaviours, additional mission archetypes, content validation, packaging.

### Stage 5 — Adoption experiments

Public demo, policy challenges, replay sharing, documentation, and measured user testing.

## 15. Acceptance rule

No amount of content or visual polish substitutes for the core acceptance test:

> A player must be able to understand a tactical consequence by following it back to code, alter the policy, and observe a deterministic change in behaviour.
