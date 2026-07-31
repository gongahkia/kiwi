# Technical Architecture

## 1. Architectural goals

The architecture must support four properties simultaneously:

1. A custom functional language can evolve independently of Python.
2. Tactical execution is deterministic and headless.
3. Significant outcomes retain source-level causal provenance.
4. The pygame client can render and inspect the simulation without becoming authoritative.

The architecture should remain simple enough for one developer and coding agents to understand. Avoid framework accumulation.

## 2. High-level system

```text
+---------------------------+
| pygame-ce desktop client  |
| editor / renderer / input |
+------------+--------------+
             | commands and read-only snapshots
+------------v--------------+
| application orchestration |
| sessions / modes / saves  |
+------+-------------+------+
       |             |
+------v------+ +----v----------------+
| DSL system  | | authoritative sim   |
| compiler VM | | fixed tick / events |
+------+------+ +----+----------------+
       |             |
       +------v------+
              |
+-------------v-------------+
| replay and causal tracing |
| hashes / provenance/query |
+---------------------------+
```

## 3. Suggested repository layout

```text
.
├── pyproject.toml
├── README.md
├── AGENTS.md
├── docs/
├── src/
│   └── kiwi/
│       ├── __init__.py
│       ├── cli.py
│       ├── domain/
│       │   ├── ids.py
│       │   ├── quantities.py
│       │   ├── geometry.py
│       │   ├── errors.py
│       │   └── versions.py
│       ├── dsl/
│       │   ├── token.py
│       │   ├── lexer.py
│       │   ├── syntax.py
│       │   ├── parser.py
│       │   ├── diagnostics.py
│       │   ├── names.py
│       │   ├── types.py
│       │   ├── typed_ir.py
│       │   ├── checker.py
│       │   ├── core_ir.py
│       │   ├── lower.py
│       │   ├── bytecode.py
│       │   ├── compiler.py
│       │   ├── runtime_values.py
│       │   ├── vm.py
│       │   ├── source_map.py
│       │   └── stdlib/
│       ├── sim/
│       │   ├── state.py
│       │   ├── clock.py
│       │   ├── commands.py
│       │   ├── observations.py
│       │   ├── intentions.py
│       │   ├── arbitration.py
│       │   ├── movement.py
│       │   ├── geometry.py
│       │   ├── perception.py
│       │   ├── communication.py
│       │   ├── cover.py
│       │   ├── weapons.py
│       │   ├── projectiles.py
│       │   ├── damage.py
│       │   ├── objectives.py
│       │   ├── events.py
│       │   ├── reducer.py
│       │   ├── snapshot.py
│       │   └── hashing.py
│       ├── trace/
│       │   ├── model.py
│       │   ├── recorder.py
│       │   ├── queries.py
│       │   ├── compare.py
│       │   └── retention.py
│       ├── replay/
│       │   ├── format.py
│       │   ├── record.py
│       │   ├── verify.py
│       │   └── checkpoints.py
│       ├── content/
│       │   ├── schemas.py
│       │   ├── loader.py
│       │   ├── validate.py
│       │   └── migrations.py
│       ├── app/
│       │   ├── session.py
│       │   ├── modes.py
│       │   ├── commands.py
│       │   └── settings.py
│       ├── render/
│       │   ├── pygame_app.py
│       │   ├── camera.py
│       │   ├── sprites.py
│       │   ├── map_view.py
│       │   ├── overlays.py
│       │   ├── terminal.py
│       │   └── fonts.py
│       └── ui/
│           ├── layout.py
│           ├── editor.py
│           ├── diagnostics_panel.py
│           ├── timeline.py
│           └── debugger_panel.py
├── tests/
│   ├── unit/
│   ├── golden/
│   ├── properties/
│   ├── integration/
│   ├── determinism/
│   ├── fixtures/
│   └── performance/
├── examples/
│   ├── policies/
│   └── missions/
└── assets/
    ├── fonts/
    ├── sprites/
    ├── audio/
    └── licences/
```

The exact filenames may change, but dependency boundaries should remain visible.

## 4. Dependency rules

### 4.1 Domain

`domain` contains stable identifiers, quantities, geometry primitives, versions, and typed errors. It uses only the standard library.

### 4.2 DSL

`dsl` contains the entire player-language toolchain. It may depend on domain quantities and identifiers but not simulation implementation details. Public tactical types may be generated from or shared through a narrow schema layer.

### 4.3 Simulation

`sim` consumes compiled policy interfaces, runtime values, and domain types. It does not parse source code during authoritative ticks. Source compilation occurs before a mission or at an explicitly modelled deployment boundary.

### 4.4 Trace and replay

`trace` records provenance from the VM and simulation. `replay` records all authoritative inputs and verifies state hashes. Neither package depends on pygame.

### 4.5 Presentation

`render` and `ui` may import public snapshots, diagnostics, source maps, and trace-query results. They must not receive writable references to simulation state.

## 5. Authoritative boundaries

### 5.1 Authority includes

- mission state;
- entity state;
- simulation tick;
- command log;
- deterministic random-stream state;
- policy bytecode and memory;
- intention collection and resolution;
- projectiles and impacts;
- objective state;
- canonical event stream;
- checkpoint hashes.

### 5.2 Authority excludes

- frame rate;
- wall-clock time;
- camera;
- animation interpolation;
- particle effects;
- audio;
- cursor position except when converted into an explicit tick-stamped command;
- window size;
- UI selection;
- decorative debris unless promoted through a documented decision.

## 6. Numeric representation

Canonical state should not use unrestricted binary floating point.

Canonical Milestone 5 representations:

- ticks and durations: integers;
- positions, displacements, and simulation distances: signed 64-bit integer millimetres;
- elevation: non-negative discrete integer layers, separate from planar vectors;
- angles: integer turns or milliradians;
- probabilities and confidence: bounded integers, for example 0–10,000;
- velocities: integer distance units per tick or fixed-point values;
- health, suppression, and integrity: bounded integers.

Exact DSL `Distance` values convert to millimetres only at the simulation
boundary: 1 metre is 1,000 millimetres and half ties round away from zero.
The renderer converts canonical values to floats for drawing. Any unavoidable
floating-point geometry must be isolated and tested for replay stability on
supported builds.

## 7. Fixed-step runtime

Each mission selects one immutable `FixedTickClock` rate from 20, 30, or 60 Hz.
The selected rate is configuration, not renderer state; it exposes an exact
rational tick duration and advances authoritative state exactly once. Fixture
and replay metadata record the selected rate when those formats are added.

The graphical loop may run at arbitrary frame rate, but simulation advances through fixed ticks.

```python
accumulator += frame_delta
while accumulator >= TICK_DURATION:
    session.apply_commands_for_tick(next_tick)
    session.advance_one_tick()
    accumulator -= TICK_DURATION
render(interpolate(previous_snapshot, current_snapshot, accumulator))
```

The headless runner advances exact tick counts without frame deltas.

## 8. Authoritative tick pipeline

Recommended phase order:

1. Apply tick-stamped player and scenario commands.
2. Advance deterministic timers and scheduled events.
3. Build immutable observations from the stable pre-evaluation state.
4. Evaluate squad coordinator programs in canonical squad order.
5. Deliver resulting assignments or broadcasts according to communication rules.
6. Evaluate operative policies in canonical entity order.
7. Collect intentions and VM trace records.
8. Validate capabilities and preconditions.
9. Arbitrate compatible intentions.
10. Resolve movement and occupancy.
11. Resolve aim, use, medical, and communication actions.
12. Spawn projectiles.
13. Advance existing projectiles and resolve impacts.
14. Apply damage, suppression, injury, destruction, and objective changes.
15. Emit canonical events and causal edges.
16. Update policy memory and entity derived state.
17. Compute checkpoint hash when scheduled.
18. Produce a presentation snapshot.

Changing this order changes semantics and requires a decision record and replay-version update.

## 9. DSL compilation architecture

The compiler is an explicit pipeline:

```text
SourceText
 -> Tokens
 -> SurfaceModule
 -> ResolvedModule
 -> TypedModule
 -> CoreModule
 -> BytecodeModule + SourceMap + CapabilityManifest
```

Each stage:

- uses immutable typed data;
- returns structured diagnostics;
- can be tested independently;
- preserves or maps source spans;
- avoids side effects except at file-loading boundaries.

The compiler output includes:

- language version;
- bytecode version;
- module hash;
- constant pool;
- function table;
- instructions;
- source map;
- type summary;
- capability requirements;
- cost metadata where statically known.

Milestone 4 represents capability requirements as a separate immutable compiler
artifact, rather than mutating the raw bytecode format. The initial manifest is
versioned and contains each policy entry point with an empty requirement tuple;
Milestone 6 populates source-linked capability requirements before execution.

## 10. VM architecture

The VM is deterministic and sandboxed by construction.

Requirements:

- no Python object access from user code;
- closed runtime-value algebra;
- explicit call frames;
- bounded instruction count;
- bounded stack depth;
- bounded allocations;
- no unbounded recursion;
- no IO;
- no wall clock;
- no implicit randomness;
- stable equality and ordering semantics;
- structured runtime faults;
- trace hooks keyed by source and expression identifiers.

A policy invocation returns one of:

```text
Success(new_memory, intentions, cost, trace_ref)
Fault(code, source_span, details, fallback_used, cost, trace_ref)
BudgetExceeded(kind, source_span, cost, fallback_used, trace_ref)
```

## 11. Simulation data model

Use plain typed data rather than a third-party ECS initially. Small squad sizes do not justify an ECS dependency before profiling.

Recommended state style:

- stable IDs;
- mappings keyed by IDs for lookup;
- sorted ID tuples for canonical iteration;
- immutable input observations;
- explicit reducer or phase functions;
- local mutable builders permitted inside a tick only if output semantics are deterministic and not exposed.

The initial kernel materialises a non-negative signed 64-bit mission tick, a
strictly entity-ID-ordered tuple of minimal entity states, immutable ID
allocator state, and a `(tick, sequence)` scheduled-event queue. State
components are added only with the task that defines their invariants;
canonical encoding is deferred to its dedicated task.

Random state is a versioned root-seed manifest plus a fixed-order tuple of
independent named PCG32 streams. Each raw draw returns immutable successor
state and a causal record; authoritative code never uses Python's random APIs.

Canonical mission-state bytes use the versioned `KWI-STATE\0` binary format:
fixed-width big-endian scalars and explicit ordered bounded collections. The
authority hash is BLAKE2b-256 over exactly those bytes; unsupported format
versions are rejected rather than reinterpreted.

The initial reducer accepts an immutable exact-tick command tuple, canonicalises
it, transitions `prepared` missions to `active`, records authorised aborts,
rejects signals until they become observations, dequeues scheduled markers,
then advances exactly one clock tick. It allocates a canonical event record for
every applied or rejected command and dequeued marker.

## 12. Command model

All external authority enters through typed commands. The initial kernel admits:

```text
StartMission
IssueSignal(signal, target)
RequestAbort
```

`SetSimulationRate` is presentation-only, and policy deployment is deferred
until policy state exists. These commands include:

- tick;
- globally unique monotonic sequence number;
- source kind;
- validated payload.

The canonical command log sorts by `(tick, sequence)` and rejects duplicate
sequences; source identifies provenance but does not break ties. The replay
stores this canonical command log.

## 13. Event model

Events are immutable tagged records. Examples:

```text
PolicyEvaluated
BranchSelected
IntentEmitted
IntentRejected
IntentSelected
MovementStarted
CoverEntered
ContactObserved
MessageSent
MessageDelivered
WeaponFired
ProjectileMoved
ProjectileImpacted
DamageApplied
OperativeInjured
ObjectiveUpdated
```

Events carry stable IDs and causal parent references where applicable. Human-readable text is derived at the UI boundary.

The initial closed algebra records applied start, abort, and signal commands;
scheduled trigger dequeues; and deterministic random draws. Its header carries
an event ID, tick, and ascending causal-parent event IDs. Canonical streams sort
by `(tick, event ID)` and reject duplicate IDs.

## 14. Replay architecture

A replay package contains:

- format version;
- application build identifier;
- mission content hashes;
- kiwi bundle hashes;
- initial state or fixture reference;
- deterministic seed manifest;
- command log;
- scheduled content events;
- checkpoint hashes;
- optional snapshots;
- optional trace references.

Verification re-executes the simulation and compares hashes. A mismatch reports the first divergent checkpoint and, where enabled, the first divergent canonical component.

## 15. Causal tracing architecture

Tracing crosses the VM and simulation boundary.

VM side records:

- invocation;
- source expression evaluation;
- observation read;
- function result;
- branch selection;
- intention construction.

Simulation side records:

- validation;
- arbitration;
- execution;
- world event;
- consequence.

Stable IDs connect these records. Trace capture must be configurable to avoid retaining every intermediate value in ordinary play.

## 16. pygame application architecture

The desktop application contains modes such as:

- boot;
- main menu;
- briefing;
- workbench;
- mission;
- debrief/debugger;
- settings.

Input is translated into application actions. Only permitted actions become authoritative commands. The mission renderer reads a presentation snapshot containing display-ready entity, geometry, overlay, and event data.

## 17. Editor architecture

The MVP editor is project-owned and intentionally limited:

- text buffer;
- cursor and selection;
- line indexing;
- insertion and deletion;
- undo and redo;
- clipboard;
- syntax token spans;
- diagnostics;
- source navigation;
- compile action.

Do not build a general text-editor framework. Store source as Unicode text, while the shipping font may support a narrower initial glyph set with fallback diagnostics.

## 18. Content architecture

Mission and entity content should be data-driven through validated versioned files. Avoid dynamic Python imports for content.

Content load flow:

```text
bytes -> parse -> schema validation -> semantic validation -> canonical content model
```

Content hashes become replay inputs.

## 19. Error handling

Boundaries return typed errors:

- compiler diagnostics;
- content validation issues;
- replay compatibility errors;
- simulation invariant violations;
- asset-load failures;
- application configuration errors.

Unexpected internal defects may retain Python tracebacks in development logs, but player-facing normal failures must be structured and concise.

## 20. Dependency policy

Initial runtime dependency target:

- pygame-ce only.

Initial development dependencies:

- pytest;
- Hypothesis when property tests begin;
- Ruff;
- one static type checker.

Add dependencies only when they remove substantial project risk. Record licence, platform, packaging, determinism, and maintenance implications.

## 21. Performance budgets

Initial target scale:

- 4–8 player operatives;
- fewer than 32 active tactical entities;
- compact map;
- 20–60 authoritative ticks per second, selected after profiling;
- graphical presentation at 60 frames per second where available;
- policy evaluation budget enforced per invocation;
- trace mode overhead measured separately.

Performance tests should define budgets in measured operations rather than relying on intuition.

## 22. Development modes

### Headless test mode

No pygame import or initialisation. Runs compiler, simulation, replay, and trace tests.

### Headless CLI mode

Compiles policies, validates content, runs fixtures, emits hashes, and verifies replays.

### Graphical development mode

Starts pygame with debug overlays and hot reload for non-authoritative assets. Policy source may be recompiled between runs.

### Release mode

Uses validated bundled content, controlled logs, recorded versions, and packaged licences.
