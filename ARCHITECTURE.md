# Technical Architecture

## 1. Architectural goals

The codebase must make simulation, language execution, replay, and causal tracing testable without rendering.

Primary requirements:

- deterministic authoritative simulation;
- strict separation between simulation and presentation;
- no user program access to host Lua state;
- headless execution;
- stable serializable state;
- data-driven missions and equipment;
- inspectable event and provenance records;
- incremental implementation in LÖVE 2D.

## 2. High-level modules

```text
Application Shell
├── Scene / State Management
├── Rendering and UI
├── Input
├── Audio
├── Asset Pipeline
└── Persistence

Game Domain
├── Campaign
├── Mission Definition
├── Squad and Equipment
├── Authoritative Simulation
├── Observation Builder
├── Intent Resolver
├── Communication
├── Damage and Cover
└── Mission Rules

Language Toolchain
├── Lexer
├── Parser
├── AST
├── Type Checker
├── Capability Checker
├── Core IR
├── Optimiser
├── Bytecode Emitter
├── Bytecode Verifier
└── Virtual Machine

Debugging and Replay
├── Event Log
├── State Snapshots
├── Replay Runner
├── Trace Recorder
├── Provenance Graph
├── Explanation Queries
└── Source Mapping
```

## 3. Authoritative boundaries

### 3.1 Simulation is authoritative

The simulation owns:

- entity state;
- physics state;
- mission clock;
- random streams;
- damage;
- perception;
- communication;
- objective state;
- intent results;
- event ordering.

The renderer may interpolate and visualise but must never authoritatively alter simulation state.

### 3.2 User programs are advisory

The VM returns values and intentions. It cannot mutate simulation state directly.

### 3.3 UI is a client of snapshots

The UI reads immutable view models derived from simulation and toolchain state.

## 4. Suggested repository structure

```text
/
├── main.lua
├── conf.lua
├── AGENTS.md
├── README.md
├── docs/
├── src/
│   ├── app/
│   │   ├── app.lua
│   │   ├── scene_manager.lua
│   │   └── services.lua
│   ├── sim/
│   │   ├── world.lua
│   │   ├── clock.lua
│   │   ├── scheduler.lua
│   │   ├── entity_store.lua
│   │   ├── components/
│   │   ├── systems/
│   │   ├── observation/
│   │   ├── intents/
│   │   ├── physics/
│   │   ├── combat/
│   │   └── missions/
│   ├── dsl/
│   │   ├── lexer.lua
│   │   ├── parser.lua
│   │   ├── ast.lua
│   │   ├── resolver.lua
│   │   ├── types.lua
│   │   ├── typecheck.lua
│   │   ├── core.lua
│   │   ├── compile.lua
│   │   ├── bytecode.lua
│   │   ├── verify.lua
│   │   ├── vm.lua
│   │   └── stdlib/
│   ├── trace/
│   │   ├── event_log.lua
│   │   ├── recorder.lua
│   │   ├── provenance.lua
│   │   ├── explain.lua
│   │   └── replay.lua
│   ├── ui/
│   │   ├── screens/
│   │   ├── widgets/
│   │   ├── editor/
│   │   ├── debugger/
│   │   └── theme/
│   ├── render/
│   ├── assets/
│   ├── campaign/
│   └── util/
├── content/
│   ├── missions/
│   ├── operatives/
│   ├── equipment/
│   ├── doctrines/
│   └── localisation/
├── tests/
│   ├── unit/
│   ├── property/
│   ├── golden/
│   ├── simulation/
│   ├── replay/
│   └── fixtures/
├── tools/
│   ├── headless_runner.lua
│   ├── content_validator.lua
│   └── replay_inspector.lua
└── vendor/
```

## 5. Simulation architecture

A data-oriented ECS-like architecture is appropriate, but avoid importing a complex framework before requirements justify it.

Recommended model:

- stable integer entity IDs;
- component tables keyed by entity ID;
- deterministic ordered iteration lists;
- systems executed in a fixed schedule;
- explicit command buffers for structural changes;
- serialization defined per component.

Do not rely on Lua table iteration order.

## 6. Fixed tick pipeline

Suggested authoritative tick:

```text
1. Apply queued external tactical signals
2. Deliver messages due this tick
3. Update environmental systems
4. Build observations
5. Evaluate squad coordinator programs
6. Apply assignments
7. Evaluate operative programs
8. Validate and queue intentions
9. Resolve movement and action arbitration
10. Step physics
11. Resolve projectile collisions and damage
12. Update perception and contact tracks
13. Update suppression and injuries
14. Evaluate mission objectives
15. Emit canonical events
16. Record trace summaries
17. Hash state and snapshot if scheduled
18. Advance tick
```

The exact order is part of the simulation contract and must be documented and tested.

## 7. Physics integration

Use `love.physics` as a constrained rigid-body substrate.

Rules:

- physics timestep is fixed;
- simulation owns creation and destruction of bodies;
- contact callbacks enqueue deterministic records rather than mutating unrelated systems immediately;
- world-to-screen conversion is presentation-only;
- body/user-data references use stable entity IDs;
- dynamic body counts remain modest;
- projectiles may use continuous collision or deterministic ray advancement where engine behaviour is insufficient.

Do not attempt a general destructible-body engine in the MVP. Use authored cover pieces with discrete damage states and replacement geometry.

## 8. Program evaluation

### 8.1 Evaluation context

Each VM invocation receives:

- immutable observation value;
- immutable previous memory value;
- program package reference;
- instruction fuel;
- heap budget;
- trace mode;
- intrinsic table.

### 8.2 Output

The VM returns:

- success or runtime error;
- new memory;
- list of intentions;
- instruction cost;
- trace records;
- emitted diagnostics.

### 8.3 Isolation

Each operative evaluation is isolated. No operative can access another operative’s memory except through explicit observations or messages.

## 9. Observation builder

The observation builder converts authoritative state into permitted data.

It must:

- apply sensor range and line of sight;
- preserve uncertainty;
- include timestamps;
- distinguish direct and relayed information;
- omit hidden fields;
- bound list sizes;
- sort values deterministically;
- provide stable serialization for trace and replay.

Observation fixtures should be testable without running a complete mission.

## 10. Intent resolution

Intent resolution occurs in stages:

1. Schema validation.
2. Capability validation.
3. Current-state validation.
4. Resource reservation.
5. Conflict arbitration.
6. Conversion to simulation actions.
7. Outcome event generation.

Every rejection should produce an explicit reason.

Example reasons:

- capability unavailable;
- target unknown;
- target stale;
- cover occupied;
- path invalid;
- weapon not ready;
- communication unavailable;
- operative incapacitated;
- conflicting higher-priority intent.

## 11. Event model

Canonical event structure:

```text
Event {
  eventId,
  tick,
  phase,
  kind,
  subjects,
  payload,
  causeRefs,
  sourceIntentId,
  sourceEvaluationId
}
```

Events are append-only during a run.

Examples:

- observation created;
- policy evaluated;
- assignment issued;
- intention accepted;
- intention rejected;
- movement started;
- projectile spawned;
- projectile impacted;
- cover damaged;
- operative injured;
- message sent;
- message delivered;
- objective changed.

## 12. Replay architecture

A replay contains:

- build and format versions;
- content hashes;
- mission definition hash;
- initial state or initial snapshot;
- program package hashes;
- tactical input stream;
- deterministic random seeds;
- periodic state hashes;
- optional snapshots;
- canonical event log;
- optional full traces.

Replay modes:

- authoritative rerun from initial state;
- fast playback from snapshots and events;
- forensic replay with traces;
- branch replay with modified doctrine.

## 13. Persistence

Separate:

- campaign save;
- doctrine source projects;
- compiled packages;
- mission replays;
- settings;
- cached editor metadata.

Use versioned, validated formats. Avoid serializing raw Lua tables through unsafe or opaque mechanisms.

A simple JSON-like or MessagePack-like schema is acceptable, provided ordering and number representation are controlled for hashing.

## 14. Rendering architecture

Rendering consumes interpolated snapshots.

Layers:

- terrain;
- cover and structures;
- operatives;
- projectiles and effects;
- fog of war;
- tactical overlays;
- selection and inspection;
- UI.

The renderer should support:

- deterministic simulation at low render rates;
- hidden debug overlays;
- screenshot-friendly telemetry;
- integer-scaled terminal fonts;
- no gameplay logic in draw methods.

## 15. UI architecture

Use a retained or hybrid UI model with stable widget IDs and explicit state.

Critical screens:

- main menu;
- campaign base or roster;
- mission briefing;
- doctrine workbench;
- deployment;
- live mission;
- post-mission debugger;
- replay browser.

The editor and debugger should be developed as reusable tools rather than hard-coded scene-specific widgets.

## 16. Asset strategy

Prefer:

- procedural primitives;
- authored low-resolution sprites;
- code-generated effects;
- palette-driven variations;
- data-defined animation;
- a consistent original bitmap font for shipping.

Codex-generated or programmatically generated assets can accelerate production, but all generated assets must be reviewed, versioned, and treated as ordinary source assets.

## 17. Dependency policy

- Keep external dependencies minimal.
- Vendor or pin essential Lua libraries.
- Record licences.
- Do not depend on a large framework for core simulation or language execution.
- Prefer test libraries and small utilities over architecture frameworks.

## 18. Performance budgets

Initial target scene:

- four friendly operatives;
- two to eight hostiles;
- dozens of cover bodies;
- dozens of projectiles over a short interval;
- policy evaluation at a lower frequency than physics where appropriate;
- full trace on selected entities only.

Optimisation priorities:

1. deterministic correctness;
2. clear profiling;
3. bounded allocations;
4. trace sampling;
5. spatial query efficiency;
6. renderer batching.

## 19. Error handling

Host code should use typed or structured error objects.

User program failures must never crash the application.

Content validation errors should fail fast during development and produce clear paths to the invalid field.

## 20. Build modes

### Development

- assertions;
- full diagnostics;
- trace options;
- debug overlays;
- content hot reload where safe.

### Test

- headless;
- fixed seeds;
- deterministic clocks;
- no audio;
- golden output support.

### Release

- validated content;
- minimal logs;
- replay compatibility checks;
- crash reporting or local diagnostic bundle where appropriate.
