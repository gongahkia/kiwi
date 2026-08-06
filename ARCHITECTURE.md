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
│       │   ├── conditions.py
│       │   ├── damage.py
│       │   ├── suppression.py
│       │   ├── firing.py
│       │   ├── objectives.py
│       │   ├── lockdown.py
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

`trace` records provenance from the VM and simulation. Its query layer consumes
only retained immutable packets and returns evidence or an explicit unavailable
result; it never reads authoritative state or infers discarded causes. `replay`
records all authoritative inputs and verifies state hashes. Neither package
depends on pygame.

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
- operative footprint: closed fixed-radius 350 millimetre planar disc;
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

The VM standard-library path can optionally retain source-mapped final List
selections and rankings plus detailed `Cover.nearest_safe` candidate records
without mutating authoritative state. Durable trace packaging and cross-phase
causal graphs remain outside this VM-facing record.

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

The initial kernel materialises a non-negative signed 64-bit mission tick and
phase, a strictly entity-ID-ordered tuple of minimal entity states, an optional
immutable bounded map with `ObstacleId`-ordered axis-aligned obstacles, an
entity-ID-ordered tuple of active movement actions, an entity-ID-ordered sparse
store of data-only policy-memory records, an
entity-ID-ordered sparse store of BLAKE2b deployed-policy versions, immutable
ID allocator state, a `CoverId`-ordered dynamic cover store, a `(CoverId,
slot index)`-ordered cover-reservation store, a `WeaponId`-ordered owner-bound
magazine store, an entity-ID-ordered sparse nonzero aim-quality store, an
entity-ID-ordered sparse nonzero suppression store, a `ProjectileId`-ordered
live point-projectile store with owner, full immutable Fire intention origin,
exact position, per-tick vector, and remaining lifetime, a pure bounded swept-
collision query,
and a projectile-impact phase that produces one projectile-ID-ordered
advancement, expiry, or impact resolution per live projectile, an
entity-ID-ordered sparse operative-condition store, and a `(tick, sequence)`
scheduled-event queue. Damage consumes only structured operative impacts, in
projectile-ID order, and retains the source impact in its transient resolution.
Combat event emission follows fire intention ID, projectile ID, damage
projectile ID, then changed-suppression entity ID order; it is transient and
allocates only the existing event-ID counter. State components are added only
with the task that defines their invariants; canonical encoding follows this
explicit state-field order.

Random state is a versioned root-seed manifest plus a fixed-order tuple of
independent named PCG32 streams. Each raw draw returns immutable successor
state and a causal record; authoritative code never uses Python's random APIs.

Canonical mission-state bytes use the versioned `KWI-STATE\0` binary format:
fixed-width big-endian scalars and explicit ordered bounded collections. The
authority hash is BLAKE2b-256 over exactly those bytes; unsupported format
versions are rejected rather than reinterpreted.

An `AuthoritySnapshot` holds the exact canonical-state payload, redundant tick,
and state hash. Restore decodes the payload and verifies its tick and hash
before returning authoritative state. It contains no display data. The separate
`PresentationSnapshot` is an immutable copied projection of display values,
including live projectiles, per-operative aim and suppression, and copied
current impact-event markers; pygame receives it rather than `MissionState`.

The initial reducer accepts an immutable exact-tick command tuple, canonicalises
it, transitions `prepared` missions to `active`, records authorised aborts,
records active-mission signals as tick-stamped observations, dequeues scheduled
markers, then advances exactly one clock tick. It allocates a canonical event
record for every applied or rejected command and dequeued marker.

After policy validation and channel arbitration, selected `MoveToward` requests
plan a bounded route against the immutable map. A successful route emits a
route-start event and activates the action; route-query and route-search
failures emit structured route-rejection events. The action persists the
route-start event ID, so later movement events retain a causal parent without
consulting presentation state.

Selected `TakeCover` requests resolve against the cover store, retain or choose
one requested-side reservation slot in canonical order, and emit a
source-linked grant or rejection event. Reservation is independent of movement
and physical occupancy.

Selected Fire execution emits one fired or rejected outcome parented by the
selected intention event. Each live projectile then emits its advancement,
expiry, or impact outcome. Damage events parent the matching impact; an injury
event parents its damage event only when severity changes. Every nonzero
suppression change retains the current-tick projectile outcomes that contributed
to it as parents. This event layer is headless, read-only with respect to
renderer state, and stores no new durable field.

`kiwi.sim.visibility` resolves pure range-limited map line-of-sight queries and
range-visible obstacle projections from immutable positions. It has no policy,
renderer, or state mutation dependency; later contact and observation phases
consume its structured result.

`kiwi.sim.contacts` owns the canonical owner-local contact store and pure
lifecycle transforms. It receives only explicit visibility-associated sightings,
retains no target entity identity, and carries required field-level evidence
event IDs through decay and canonical state. ABI version 4 projects exactly one
owner-local nearest contact by planar squared distance and contact-ID tie-break;
the projection contains no true target, elevation, or owner identity.

`kiwi.sim.messages` defines pure typed, addressed radio messages and immutable
delivery-ordered inbox values. Its canonical authority ledger assigns global
send sequences, delivers at the next tick, discards expired entries, and feeds
owner-local ABI version 2 inboxes without a shared mutable blackboard or
presentation dependency. `kiwi.sim.communication` materialises source-linked
send events and emits delivery events in ledger order before policy evaluation;
each delivery parents its message send. A `ContactReport` payload remains raw
inbox data; it has no implicit contact-store merge or target association.

`kiwi.sim.signals` defines immutable current-tick squad or entity-targeted
signal observations. The reducer accepts them only for active missions, retains
their command and event provenance in canonical state, and feeds owner-local
ABI version 3 values without exposing a writable blackboard.

The headless runner consumes an immutable command log, rejects commands outside
its exact tick window, and groups canonical commands per tick without frames,
wall-clock input, or presentation state. It returns the final state and the
complete canonically ordered event stream. Configured checkpoint intervals
capture authority-only snapshots. The determinism harness repeats those inputs
and reports the earliest checkpoint mismatch with a canonical field path.

The content package validates versioned fixture JSON into immutable primitive
models without importing simulation. The simulation bootstrap consumes those
canonical primitive values to allocate initial authority state; it never reads
files during ticks.

The version-7 runtime observation model is an immutable simulation value with
owner-visible entity ID, planar position, exact aim quality, aim ceiling,
suppression, health, protection, derived injury severity, incapacitation,
stabilization, delivered inbox, current signals, tick, `nearest_contact:
Option<Contact>`, and range-visible cover records. A conversion at the
simulation/DSL boundary produces closed lexically ordered DSL records; no
renderer or hidden-world reference crosses that boundary.

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
message sends and deliveries; scheduled trigger dequeues; and deterministic
random draws. Its header carries an event ID, tick, and ascending causal-parent
event IDs. Canonical streams sort by `(tick, event ID)` and reject duplicate IDs.

## 14. Replay architecture

A replay package contains:

- binary `KWI-RUN\0` format version;
- application build and simulation-version identifiers;
- mission and deployed policy-version hashes;
- self-verifying initial authority snapshot and matching seed;
- fixed tick rate, canonical external command log, and checkpoint hashes.

Version `1` accepts only exact version-one packets; it has no migration or
compatibility runner. Seeking snapshots, trace references, content resolution,
and divergence reports are introduced by their owning replay milestones.
Replay recording captures the initial authority snapshot before headless
execution, canonicalises its external commands, derives policy identities from
the immutable bindings used for that execution, and copies only checkpoint
hashes into the packet.
Verification restores the packet's initial snapshot, requires matching binding
versions, and replays each checkpoint interval headlessly before comparing its
canonical state hash. It returns structured initial-snapshot, policy-version,
or checkpoint-hash failures. A checkpoint failure retains the earliest index,
tick, expected hash, and reconstructed hash. With a matching `.dseek` sidecar,
it also retains the first differing canonical-state field path and expected and
reconstructed values.
An optional strict `KWI-SEEK\0` v1 sidecar binds periodic self-verifying
snapshots to the canonical replay hash. Seeking rejects mismatched sidecars or
bindings, restores the nearest preceding checkpoint, then runs only the
remaining authoritative ticks. It does not alter `.drun` v1.
An optional strict `KWI-SOURCE\0` v1 `.dsrc` sidecar binds exact historical
UTF-8 source, language versions, deployed bytecode, selected entry functions,
and canonical bytecode source maps to that same replay hash. Consumers require
its entity-ID-ordered policy-version manifest to match the replay before source
navigation; it does not alter `.drun` v1 or authoritative execution.
Run-comparison admission is a pure replay-layer check. It requires identical
build, simulation version, mission hash, initial snapshot, seed, tick rate,
and canonical commands while retaining policy-version deltas as ordered output.
It never runs an incompatible replay or reads presentation state.
Compatible headless runs compare policy evaluations by `(tick, entity ID)` and
emitted intentions by `(tick, issuer entity ID, policy order)`. Allocation-only
invocation and intention IDs do not create a difference; source provenance and
validated intention payloads do.
Retained causal consequences compare by `(tick, kind, subject entity IDs)` and
return all added, removed, and changed records in canonical key order.
Run-local trace nodes and authority event IDs do not create a consequence
difference.
The headless CLI records policy-free kernel fixtures as replay packets, verifies
them without renderer access, inspects immutable manifest metadata, and reports
baseline compatibility plus policy-version manifest deltas. Policy-bundle
resolution remains outside this boundary.

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

`kiwi.trace.model` defines the immutable run-local graph records and typed
edges; `kiwi.trace.format` encodes one `KWI-TRACE\0` version-1 packet with a
run-state hash and no authority-state reference. The trace package may depend
on domain, DSL source, and simulation event schemas, but no authoritative
package imports it. Its decision-level policy-lifecycle projector consumes the
canonical policy event phase and matching state hash to retain each intention
origin, policy-evaluation/emission/resolution event IDs, arbitration outcome,
and competitor link. Its run projector extends that graph with every canonical
world event and header-parent edge, bridges retained projectile provenance to
impacts, and emits injury consequences. Retention, queries, and replay packaging
extend this boundary in later milestones. `TraceRetentionPolicy` selects Summary,
Decision, or Full detail and applies an optional trailing-tick window plus bounded
record and edge limits before a packet is constructed; it never changes authority.

The VM's opt-in expression capture retains source-map entries in execution
order on `VMRunResult`; `PolicyEvaluation.invocation_id` identifies the owning
evaluation. Its separate opt-in observation-read capture attaches immutable
field metadata only to the policy input, then records each `LoadField` with its
source-map entry, canonical observation path, closed value, ordered evidence
event IDs, and applicable contact confidence and age. An opt-in branch capture
records only executed `then` or `else` conditional arms and `Some` or `None`
Option-pattern arms with their source-map entries. Standard-library capture
records `List.filter` retained source indices, `List.find` and `List.min_by`
selected source indices, and `List.sort_by` ranking source-index order, together
with the number of items whose callbacks were evaluated; the same switch enables
detailed Cover candidate capture. Metadata is stripped from top-level VM results,
and all record streams are non-authoritative and omitted unless requested.

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

`kiwi.render.pygame_lifecycle` exclusively owns the minimal pygame-ce process
lifecycle. `initialise_pygame()` initialises pygame-ce without creating a
window, and `quit_pygame()` releases it; only `kiwi.app` and `kiwi.render` may
import pygame. Headless packages and commands never import or initialise it.

`kiwi.render.pygame_app` creates a 960x540 window around a separate 480x270
logical canvas. `kiwi.render.camera.Camera` projects copied presentation-world
coordinates with positive world Y upward; map drawing and final scaling are
strictly display transforms and cannot write authority state.
The current tactical renderer draws copied map geometry, operative positions,
planned paths, owner-local contact estimates with uncertainty rings, explicit
sensor-radius and visible-geometry overlays, and an optional display objective
marker. It also draws copied cover height and integrity, contact-facing threat
rays, and exact-position slot occupancy markers. Those occupancy markers omit
reservations and predicted movement; all of these display values cannot define
objective mechanics or write authority state.

`kiwi.render.bitmap_font` loads bundled BigBlue Terminal (native 8x12) with
antialiasing disabled, then uses integer unfiltered scaling. Its CC-BY-SA-4.0
licence, attribution, release URL, and SHA-256 are retained in the packaged
render asset manifest.

`kiwi.content.missions` validates versioned mission JSON at the content
boundary. The headless `kiwi.app.mission_loading` adapter then allocates map
and cover authority IDs from canonical content order. The resulting
`MissionState` remains renderer-independent; named regions remain content
data until the corresponding objective and deployment rules consume them.

`kiwi.app.glasshouse_players` adds the four fixed player deployments,
generic weapon inventories, bounded compiled DSL policies, and declared
capabilities above that mission boundary. It also binds Glasshouse's named
objective and extraction regions to one canonical squad objective. Policy
sources remain closed DSL files and compilation failures are structured
diagnostics. It also schedules Glasshouse's one-shot 90-second lockdown, which
is resolved only by headless authority.

`kiwi.app.glasshouse_hostiles` appends three project-authored hostile
roles using the same compiled policy binding, capability, memory, weapon, and
headless execution interfaces as the player roster.

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

`kiwi.ui.editor` provides the headless immutable source buffer, one-based
Unicode-code-point line index, cursor selection, and logical scroll state. It
does not import pygame, mutate authority, or define display glyph geometry.
Edits are immutable and retain a bounded undo/redo history; clipboard exchange
is string-only data passed to or from the platform adapter.
`kiwi.ui.syntax` derives canonical source-provenance-preserving style spans
from lexer tokens and errors. `kiwi.render.source_view` is the only consumer
that imports pygame to render those spans through the bitmap font.
`kiwi.ui.diagnostics` projects structured compiler diagnostics into canonical
inline line ranges and panel rows; `kiwi.render.diagnostics_view` renders those
read-only projections without changing source, compiler, or authority state.
`kiwi.ui.compile_output` compiles immutable editor text through the existing
closed DSL stages and returns either source-bound diagnostic presentation or
immutable bytecode metadata. `kiwi.render.compile_output_view` renders only
that outcome; it cannot execute policies or alter editor source.
`kiwi.ui.development_picker` discovers explicit policy and kernel-fixture roots
in canonical order and loads only a selected file through content boundaries.
`kiwi.render.development_picker_view` consumes that immutable picker state.
`kiwi.ui.timeline` projects retained causal records into chronological tick and
node-ID entries; `kiwi.render.timeline_view` renders only this read-only
selection state.
`kiwi.ui.causal_chain` projects a selected retained trace node, direct links,
and canonical causal ancestors without inferring discarded evidence.
`kiwi.render.causal_chain_view` renders this immutable panel only.
`kiwi.ui.historical_source` selects only replay-archive source and exact
bytecode source-map expression spans; it never highlights current edited source.
`kiwi.render.historical_source_view` renders that immutable pane and its
source-bound highlight underlines.
`kiwi.ui.trace_navigation` follows retained causal edges from trace to
archive-bound source and from selected historical expressions to retained descendants.
`kiwi.ui.run_comparison` gates policy, state, and consequence deltas on
the replay compatibility baseline; `kiwi.render.run_comparison_view` renders the
read-only comparison outcome.
`kiwi.app.settings` owns versioned non-authoritative UI/font settings with
safe default fallback; `kiwi.render.settings_view` renders their integer scale summary.

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
