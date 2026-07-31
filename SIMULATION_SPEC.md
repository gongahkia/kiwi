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

Authority advances in integer ticks. Each mission selects one immutable tick
frequency through profiling and records it in replay metadata. Candidate values
are 20, 30, or 60 ticks per second. The initial kernel represents one tick as
an exact rational duration and advances mission state one tick at a time.

All authoritative durations are integer ticks or exactly converted into ticks during content validation.

### 2.2 Frame independence

Rendering frame time does not affect authoritative state. The graphical client may interpolate between snapshots.

### 2.3 Scheduling

Scheduled events use `(tick, sequence)` ordering. The initial immutable queue
allocates a local non-negative signed 64-bit sequence beginning at zero, sorts
pending events by that key, and removes events only at their exact tick. Queue
state is authoritative. Scheduled trigger dequeues are canonical events; their
state effects are added with the reducer.

### 2.4 External command ordering

The initial authority command algebra is `StartMission`, `IssueSignal`, and
`RequestAbort`; it cannot directly move, attack, heal, or otherwise control an
entity. Each command records a tick, a globally unique non-negative signed
64-bit sequence, and player or scenario source. Canonical command logs sort by
`(tick, sequence)` and reject duplicate sequences. Signals are typed,
content-defined identifiers and may target the squad or one entity; they become
policy observations only when communication is implemented.

The initial reducer accepts only commands stamped for the current mission tick.
`StartMission` transitions `prepared` to `active`; `RequestAbort` transitions
`active` to `abort_requested`; signals produce structured
`signals_unavailable` rejections until their observation semantics are added.
It then dequeues scheduled markers, records canonical events, and advances one
tick.

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
- obstacle.

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
  map_geometry
  operatives
  obstacles
  cover
  projectiles
  contacts
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

The initial kernel materialises `tick`, `entities`, `id_allocator`, and
`scheduled_events` first. Each entity is an immutable `(entity ID, world
position)` value; entity tuples are strictly ascending by entity ID. Later
state fields are added only when their own invariants and canonical
representation are defined.

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

The initial observation ABI is version `1`: each operative input contains only
its own entity ID, planar position, and the current tick. Contacts, allies,
geometry, signals, messages, objectives, and elevation are absent until their
respective authority models define explicit observable semantics.

The initial builder consumes one validated `MissionState` and produces an
entity-ID-ascending immutable tuple before any policy executes. Successor
state changes cannot alter that tuple.

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

The initial query takes one observer position, one target position, and the
immutable map. It reports structured failures for missing maps and out-of-bounds
endpoints. Different elevation layers are blocked. On the same layer, the exact
closed centre-to-centre segment is occluded by a same-layer closed obstacle
rectangle, including endpoint and corner contact. Obstacles are checked in
ascending `ObstacleId` order; the first intersected ID is retained as the
canonical blocker. A sensor range is a non-negative canonical millimetre radius
with inclusive integer squared-distance comparison; an out-of-range target is
blocked before elevation or obstacle evaluation. The initial visible-geometry
projection contains same-layer obstacle rectangles whose nearest point is in
range, in ascending `ObstacleId` order. It does not apply obstacle occlusion to
hide static geometry. Field of view and policy exposure remain later tasks.

### 8.2 Contacts

Visible enemies create or update contact estimates. The initial contact value
includes a stable local contact ID, owner entity ID, estimated position,
non-negative uncertainty radius, inclusive 0–10,000 basis-point confidence,
and last observation tick. Its age is the exact non-negative difference from a
supplied current tick. It deliberately contains no hidden target entity ID,
true state, evidence, classification, or velocity before their respective
models are defined.

`ContactStore` is an immutable tuple ordered by `(owner entity ID, contact ID)`
and a lifecycle tick. A visibility-associated `ContactSighting` creates a new
allocated contact when its ID is absent, or replaces the specified existing
owner-local contact. Sighting input is canonically sorted before allocation; no
target entity ID is retained or used for automatic association. A sighting with
zero confidence removes an existing contact and does not allocate a new one.

On each active reducer tick, contacts advance through the current tick before
policy evaluation. Each elapsed tick subtracts 100 basis points of confidence
and adds 100 millimetres of uncertainty. A contact is lost and removed exactly
when its confidence reaches zero. Its last observation tick remains unchanged
while it decays, so reported age remains exact.

### 8.3 Provenance

Each observation field that may influence kiwi carries or can resolve to
provenance IDs. Every contact stores a complete canonical mapping for estimated
position, uncertainty radius, confidence, and last-observed tick. Each mapping
contains one to 64 unique ascending `EventId` values; a direct sensor event and
later message-delivery events may both contribute. Contact creation and update
require this mapping, while deterministic decay preserves it. Contact evidence
IDs must already be allocated authority event IDs, so canonical state cannot
refer to a future event.

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

The initial invocation phase receives entity-ID-ordered external policy
bindings. A binding names one compiled two-argument policy entry, initial
record memory with its schema, and immutable VM budgets. For each bound entity,
the phase uses the pre-phase stored memory when present or the binding's initial
memory, allocates a policy-invocation ID in entity order, and retains the raw VM
result. It only advances the invocation-ID allocator; result validation,
fallback, and memory updates occur in later phases.

The active-tick reducer runs those phases after commands and scheduled markers:
invocation, validation, hold-fallback selection, intention arbitration, policy
event emission, then memory and deployed-version persistence. Policies do not
run while a mission is prepared or abort-requested.

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

The initial `IntentionOrigin` authority value stores the identity and
provenance fields with typed intention, entity, policy-invocation, and
expression IDs plus the exact DSL source span. Its action channel is derived
from the closed intention kind, so provenance cannot assert a channel
inconsistent with its request. Payload decoding is deferred to validation.

### 11.2 Validation

Validation checks:

- capability;
- entity state;
- target form;
- current resource availability;
- basic range or existence where required;
- content constraints.

The initial validator accepts `Wait { duration: Duration }` and
`MoveToward { target: Position }`. Wait duration must be positive. MoveToward
requires exactly `Position { x: Distance, y: Distance }`; its exact planar
coordinates convert to canonical millimetres with the domain rounding rule and
inherit the issuer's current elevation layer during route planning. Both occupy
`locomotion`. Other named core kinds return the structured
`I002_UNSUPPORTED_KIND` result until their payload models exist. Malformed
records return stable `I001` through `I005` validation codes; policy-result and
VM failures retain a structured `P001` through `P003` result for deterministic
fallback.

`Wait` requires the source-linked `wait` capability and MoveToward requires
`move_toward`. Each policy binding has an immutable lexically ordered set of
available capabilities. A missing declared requirement prevents VM execution
and records `P004_CAPABILITY` with the requirement span; decoded requests
repeat the same availability check.

The initial fallback resolves every failed policy validation, including VM
faults, to `hold`: it preserves that invocation's input memory and emits no
intentions. The `policy_evaluated` event retains the original structured
failure, so fallback is visible rather than treated as a successful result.

### 11.3 Arbitration

Intentions compete within action channels, for example:

- locomotion;
- weapon;
- interaction;
- medical;
- communication.

Recommended rule: first valid intention in returned order wins per exclusive channel, with compatible channels allowed together. Every rejection has a reason event.

The initial core mapping is closed and explicit: `MoveToward`, `TakeCover`,
and `Wait` use `locomotion`; `Aim` and `Fire` use `weapon`; `Use` uses
`interaction`; `Stabilise` uses `medical`; and `Emit` uses `communication`.
`Wait` therefore excludes another locomotion request but remains compatible
with weapon, interaction, medical, and communication requests. Payload
decoding and validation are separate from this kind-and-channel definition.

The initial arbitration phase allocates one intention ID for every validated
candidate in entity-ID then returned-list order. It attaches invocation and
source provenance, then selects the first candidate in each entity channel.
Later candidates in an occupied channel are retained as `channel_occupied`
rejections with the selected competing intention ID; validation failures create
no candidates.

Each policy pass emits a `policy_evaluated` event for every invocation, an
`intention_emitted` event for every validated candidate, then exactly one
`intention_selected` or `intention_rejected` event for that candidate. Candidate
events name their policy event as their sole causal parent; resolution events
name their candidate event. Events are allocated in that phase order, and then
in canonical entity and returned-list order.

### 11.4 Execution

Selected intentions become state transitions or longer-lived action states. A
selected MoveToward plans a route from the issuer's current position. A
successful nontrivial path starts or replaces that entity's movement action;
the action retains the route-start event ID. A selected request for the active
route target retains the action. A one-waypoint path clears any prior movement
action. Query or bounded-search failures leave the prior action intact and emit
a structured route-rejection event. Route-start and route-rejection events
parent the corresponding selection; movement progress, block, and arrival
events parent the retained route-start event.

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

The initial operative footprint is a closed planar disc with a fixed radius of
350 millimetres, centred at the operative's `WorldPosition`. Elevation remains
separate: only equal-elevation geometry can collide. Boundary contact counts as
collision. Movement, obstacle clearance, operative separation, and later
projectile-versus-operative tests use this same disc, expressed entirely in
integer millimetres; no float geometry or physics engine is authoritative.

Stance, injury, equipment, and animation do not alter the footprint in the
initial movement model. Any later variable footprint requires a new authority
field, collision rules, canonical-format update, and replay decision.

### 12.1.1 Map and obstacle geometry

An optional tactical map is a non-empty closed axis-aligned `WorldRectangle`
in signed 64-bit millimetres. Its obstacle tuple is immutable and strictly
ascending by `ObstacleId`. Each obstacle is a non-empty closed axis-aligned
rectangle wholly contained by the map and has a discrete `ElevationLayer`.
The map validates entity centres remain within its closed boundary; disc
clearance from boundaries and obstacles is resolved by movement collision.
Obstacle overlap is represented faithfully and has no implicit merge rule.

### 12.2 Pathing

A path query pairs one immutable map with same-elevation start and goal
positions. Query preparation returns a stable structured failure for a missing
map, elevation mismatch, or out-of-bounds endpoint; it does not silently clamp
coordinates. A `Path` stores an ordered immutable tuple of exact
`WorldPosition` waypoints including the query start and goal. A one-waypoint
path represents an already-arrived query; otherwise adjacent waypoints must be
distinct. Pathfinding and obstacle clearance are separate from query
precondition validation.

The MVP uses a same-elevation visibility graph. Its candidates are the exact
endpoints plus valid obstacle-corner points one millimetre beyond the operative
disc's 350 millimetre conservative axis-aligned clearance. Segments crossing
the closed inflated obstacle rectangles are absent. The resolver considers at
most 64 same-layer obstacles, uses exact Manhattan edge cost, and runs Dijkstra
with `(cost, ordered waypoint coordinates)` as its canonical tie key. It emits
a structured blocked-endpoint, obstacle-budget, or no-route result rather than
using host exceptions for ordinary routing outcomes.

### 12.3 Local movement

An active movement action stores its entity, endpoint-inclusive path, next
waypoint index, and dominant-axis segment progress. Active missions advance
each action by at most 100 millimetres per tick before the authoritative clock
advances. For a segment from `(x0, y0)` to `(x1, y1)`, progress uses
`max(abs(x1-x0), abs(y1-y0))`; each coordinate is reconstructed with nearest
integer rounding and ties away from zero. Reaching an intermediate waypoint
starts the next segment at zero progress; the final waypoint removes the
action.

Each attempted segment sweeps the closed 350 millimetre disc against the map
boundary and same-elevation obstacle rectangles using exact integer
squared-distance comparisons. A disc may neither contact the boundary nor an
obstacle. Movement resolves entity IDs ascending. Each candidate must remain
more than 700 millimetres from every accepted lower-ID trajectory and every
unprocessed entity's current position on the same elevation; a blocked
candidate retains its prior position and action progress. Collision and
separation emit exactly one canonical progress, block, or arrival event per
active action. Each event retains the entity, start, attempted, and result
positions; a block retains its stable map-collision or operative-separation
reason.

Subsequent local movement phases resolve:

- desired velocity;
- acceleration limit;
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

Version 1 uses independent PCG XSH RR 64/32 streams derived with fixed
SplitMix64 arithmetic from one unsigned 64-bit mission seed. The initial API
draws raw uniform unsigned 32-bit values only; distributions are added only
with an explicit bounded conversion rule. Each draw records:

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

At configured checkpoints, serialise canonical state with `KWI-STATE\0` version
`8` and hash the exact bytes with BLAKE2b-256. The binary encoder uses
fixed-width big-endian scalars and explicitly ordered bounded collections;
versions `1` through `7`, unsupported versions, and noncanonical values are
rejected.

Exclude:

- presentation state;
- Python object metadata;
- human-readable logs;
- optional full traces if they do not affect authority.

Include:

- all authority that can influence future ticks;
- random-stream state;
- map bounds and obstacle geometry;
- active movement actions;
- contact estimates and field evidence event IDs;
- policy memory;
- policy versions;
- pending messages and scheduled events;
- command cursor.

## 22. Snapshots

### 22.1 Replay checkpoints

Periodic canonical snapshots allow faster seeking and divergence analysis.
An authority snapshot carries the exact canonical state payload, its tick, and
the BLAKE2b-256 state hash. Restoration rejects malformed payloads and tick or
hash mismatches before returning mission state.

### 22.2 Presentation snapshots

A separate, non-canonical read model contains display information. The current
`PresentationSnapshot` copies the tick, phase tag, optional map bounds and
ID-ordered obstacles, ID-ordered operative positions, and each active
operative's endpoint-inclusive planned path. Its coordinates are display-only
floats derived from authoritative millimetres; it carries no `MissionState`,
entity, map, or path object reference and is never encoded or hashed as
authority. It also admits one optional display objective marker; the current
authority projection leaves it absent until objective state is implemented.
Render interpolation and later overlays may derive further values from this
snapshot.

Do not confuse the two formats.

## 23. Headless runner

The headless runner advances an exact non-negative tick count using a supplied
fixed clock and immutable command log. It rejects commands outside the executed
tick window and returns the final authority state with its canonical event
stream. It has no frame or presentation inputs. An optional positive checkpoint
interval captures the initial state, each interval boundary, and the final
state. The determinism harness repeats identical inputs and reports the earliest
different checkpoint with the first canonical field path.

The CLI must eventually support:

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
