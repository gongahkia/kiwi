# Deterministic Simulation Specification

## 1. Scope

This document specifies the authoritative tactical simulation. The simulation is intentionally game-specific. It is not a general physics engine and does not attempt continuous rigid-body realism.

The MVP must support:

- fixed-step real-time execution;
- small squads;
- movement through obstacle geometry;
- cover occupancy and exposure;
- incomplete perception;
- communication;
- aiming and physical projectile travel;
- damage, injury, suppression, and stabilisation;
- objectives and extraction;
- deterministic replay and causal tracing.

## 2. Time model

### 2.1 Tick

Authority advances in integer ticks. Select the tick frequency through profiling and record it in replay metadata. Candidate values are 20, 30, or 60 ticks per second.

All authoritative durations are integer ticks or exactly converted into ticks during content validation.

### 2.2 Frame independence

Rendering frame time does not affect authoritative state. The graphical client may interpolate between snapshots.

### 2.3 Scheduling

Scheduled events use `(tick, sequence)` ordering. Sequence values are allocated deterministically.

## 3. Determinism contract

A run is reproducible when these inputs match:

- application and simulation semantic version;
- mission and content hashes;
- initial canonical state;
- policy bytecode and standard-library versions;
- seed manifest;
- command log;
- supported platform constraints documented by the project.

The simulation must avoid:

- wall-clock reads;
- OS randomness;
- unordered iteration where order matters;
- canonical floats without a documented policy;
- object memory addresses;
- hash randomisation dependence;
- external physics authority;
- renderer callbacks.

## 4. Canonical numeric model

Canonical spatial units:

- position, displacement, and distance: signed 64-bit integer millimetres;
- elevation: non-negative discrete layers, with layer zero as the default;
- angle: integer turn units;
- speed: millimetres per tick;
- probability/confidence: integer basis points;
- health/suppression: integer ranges;
- projectile lifetime: ticks.

Exact DSL `Distance` values cross into simulation geometry as 1 metre = 1,000
millimetres with nearest rounding and half ties away from zero. Planar vectors
do not implicitly cross elevation layers; arithmetic rejects signed-64-bit
overflow. All future division specifies a named deterministic rounding mode.

## 5. Stable identifiers

Every durable object has a typed stable ID:

- entity;
- operative;
- contact;
- cover;
- projectile;
- intention;
- event;
- policy invocation;
- trace node;
- objective;
- message.

IDs must not depend on Python object identity. Dynamic IDs use immutable,
type-local counters starting at one and increasing through the positive signed
64-bit range. Allocation fails deterministically on exhaustion. Content-derived
IDs, if introduced, must define an equally canonical scheme.

## 6. State model

Canonical mission state contains:

```text
MissionState {
  tick
  entities
  operatives
  obstacles
  cover
  projectiles
  objectives
  messages_in_flight
  scheduled_events
  command_cursor
  random_streams
  policy_memories
  policy_versions
  scenario_state
}
```

Mappings are serialised and iterated in canonical key order.

## 7. Observation cycle

Observations are built from the stable state at the beginning of the policy-evaluation phase.

Each operative receives:

- own observable state;
- visible geometry and cover;
- local contact estimates;
- observable allies;
- delivered messages;
- current high-level signals;
- objective information allowed by the scenario;
- policy-assigned role and target;
- simulation tick.

The observation must not contain writable references or hidden entity state.

## 8. Perception

### 8.1 Visibility

Visibility considers:

- sensor range;
- field of view where applicable;
- obstacle and cover occlusion;
- stance and elevation abstraction;
- lighting or smoke only when later introduced;
- target visibility characteristics.

Use deterministic integer geometry algorithms.

### 8.2 Contacts

Visible enemies create or update contact estimates. A contact includes:

- stable local contact ID;
- estimated position;
- uncertainty radius;
- confidence;
- last observation tick;
- estimated velocity;
- classification estimate;
- evidence source IDs.

When visibility is lost, the contact may persist and decay according to documented rules.

### 8.3 Provenance

Each observation field that may influence kiwi carries or can resolve to provenance IDs. For example, a contact estimate can link to the sensor event and prior message that formed it.

## 9. Communication

### 9.1 Messages

Messages are immutable typed values with:

- sender;
- channel;
- payload;
- send tick;
- delivery tick;
- expiry tick;
- deterministic sequence;
- provenance.

### 9.2 Delivery

The first prototype may use immediate same-tick or next-tick delivery. Later content may configure range, delay, relay, and loss. The chosen semantics must be explicit and replayed.

### 9.3 No shared mutable memory

Squad coordination uses assignments, observations, and messages, not a mutable global blackboard.

## 10. Policy evaluation

For each applicable entry point:

1. Build immutable runtime values from observation and memory.
2. Invoke the deterministic VM with budgets.
3. Record success, fault, or budget exhaustion.
4. Validate returned memory.
5. Attach invocation and expression provenance to returned intentions.
6. Use deterministic fallback on failure.

Evaluation order is canonical by policy layer and entity ID. Policies cannot observe changes made by earlier policies in the same evaluation phase unless a later explicit phase permits it.

## 11. Intention lifecycle

### 11.1 Creation

An intention receives:

- intention ID;
- issuer;
- kind;
- payload;
- action channel;
- source invocation;
- source expression;
- policy order index;
- creation tick.

### 11.2 Validation

Validation checks:

- capability;
- entity state;
- target form;
- current resource availability;
- basic range or existence where required;
- content constraints.

### 11.3 Arbitration

Intentions compete within action channels, for example:

- locomotion;
- weapon;
- interaction;
- medical;
- communication.

Recommended rule: first valid intention in returned order wins per exclusive channel, with compatible channels allowed together. Every rejection has a reason event.

### 11.4 Execution

Selected intentions become state transitions or longer-lived action states. Some complete immediately; others take ticks.

### 11.5 Outcome

Every selected intention produces an outcome record:

- started;
- completed;
- interrupted;
- failed;
- superseded;
- partially completed.

Outcomes link to resulting world events.

## 12. Movement

### 12.1 Representation

Operatives use circles, capsules, or simple convex footprints. Select one representation during the movement milestone and document it.

### 12.2 Pathing

The MVP may use:

- navigation grid;
- waypoint graph;
- visibility graph;
- hybrid pathing.

Path generation must use canonical tie-breaking. If A* is used, equal-cost nodes require stable ordering.

### 12.3 Local movement

Movement resolves:

- desired velocity;
- acceleration limit;
- obstacle collision;
- operative separation;
- occupancy contention;
- stance and injury modifiers.

Avoid fully realistic crowd dynamics. Behaviour should remain explainable.

### 12.4 Contention

When multiple operatives seek the same location or cover slot, resolve using documented priority and ID tie-breaks. Emit contention events.

## 13. Cover

A cover segment includes:

- endpoints or shape;
- outward directions;
- height class;
- integrity;
- material;
- occupancy slots;
- blocking properties.

Exposure to a threat is computed from geometry, stance, and contact estimate. Because contacts are uncertain, policy-facing exposure may differ from ground truth. Record both where useful for explanation.

## 14. Aiming

Aim state includes:

- target estimate;
- accumulated aim quality;
- movement penalty;
- suppression penalty;
- injury penalty;
- weapon characteristics;
- last update tick.

Aim progression is deterministic. If dispersion uses randomness, it draws from a named stream and records the draw.

## 15. Projectiles

### 15.1 Spawn

A successful fire resolution creates a projectile with:

- ID;
- owner;
- source intention;
- position;
- velocity;
- radius or ray representation;
- damage profile;
- remaining lifetime;
- provenance.

### 15.2 Advance

Advance projectiles in canonical ID order. Use swept-segment intersection to prevent tunnelling at target scales.

### 15.3 Impact

Select the earliest collision along the projectile segment. Equal-time ties use documented stable ordering. Emit impact and consequence events.

## 16. Randomness

Randomness is permitted only through named deterministic streams, for example:

- weapon dispersion;
- damage variation;
- scenario spawn variation;
- enemy policy choices.

Each draw records:

- stream ID;
- draw index;
- input range or distribution;
- result;
- causal purpose.

Where practical, prefer deterministic geometry and explicit uncertainty over random rolls.

## 17. Damage and injury

The MVP uses a bounded abstraction:

- health;
- protection;
- injury severity;
- incapacitated state;
- stabilised state.

Damage resolution may include hit region categories only if they create meaningful policy decisions. Avoid anatomical complexity.

All state changes link to projectile or action events.

## 18. Suppression

Suppression increases from:

- nearby projectile paths;
- impacts;
- explosions;
- ally injury;
- scenario effects.

It decays deterministically. Policies observe suppression as an explicit quantity.

## 19. Medical action

`Stabilise(ally)` requires:

- capability;
- proximity;
- action duration;
- uninterrupted or interruption rules;
- target injury state.

The outcome links back to the medical intention and any interruption cause.

## 20. Objectives

MVP objective states include:

- inactive;
- active;
- progressing;
- completed;
- failed.

Examples:

- retrieve item;
- enter region;
- hold region for ticks;
- extract listed entities;
- survive until tick;
- protect entity.

Objective transitions are canonical events.

## 21. State hashing

At configured checkpoints, serialise canonical state into a stable byte representation and hash it.

Exclude:

- presentation state;
- Python object metadata;
- human-readable logs;
- optional full traces if they do not affect authority.

Include:

- all authority that can influence future ticks;
- random-stream state;
- policy memory;
- pending messages and scheduled events;
- command cursor.

## 22. Snapshots

### 22.1 Replay checkpoints

Periodic canonical snapshots allow faster seeking and divergence analysis.

### 22.2 Presentation snapshots

A separate, non-canonical read model contains display information. It may include derived floats and interpolatable states.

Do not confuse the two formats.

## 23. Headless runner

The CLI must support:

- run mission for N ticks;
- run until completion or failure;
- emit checkpoint hashes;
- record replay;
- verify replay;
- enable trace level;
- query selected consequences;
- compare two runs.

## 24. Invariant failures

Simulation invariants include:

- unique IDs;
- valid entity references;
- bounded canonical values;
- no negative ammunition or timers;
- valid memory schema;
- sorted canonical queues;
- no unresolved action channel conflicts after arbitration.

Development builds should fail loudly with structured context. Release builds should terminate or quarantine corrupted runs rather than silently continue.

## 25. MVP acceptance criteria

- Same input run produces identical hashes repeatedly.
- Graphical and headless runs produce identical authority.
- Movement and path ties are stable.
- Policy evaluation order is stable.
- Projectiles produce visible deterministic impacts.
- Injury and objective state are replayable.
- Trace IDs connect intentions to outcomes.
- No pygame import is required for authoritative tests.
