# Design Decisions and Open Questions

This file is the authoritative record of settled product and technical decisions. Any implementation change that contradicts a settled decision requires an explicit update here, a rationale, and corresponding specification changes.

## 1. Settled decisions

### D-001: The project is a programmable hybrid netspace tactics game

KIWI // Terminal uses a Cyberpunk-era netrunner terminal fiction: programmable daemon bundles confront ICE, trace pressure, and payload objectives. Existing deterministic tactical authority remains the abstract resolution model; presentation and content map it to netspace without direct player control.

### D-002: Python is the host implementation language

Python implements the compiler, VM, simulation, replay, causal-debugger model, content loaders, tests, and desktop application. This decision optimises for compiler experimentation, traceability, headless testing, and iteration speed.

Python is not exposed as the player scripting language.

### D-003: pygame-ce is the graphical application layer

pygame-ce owns the OS window, input collection, audio playback, bitmap-font rendering, visual effects, and frame presentation. It must not own authoritative tactical state.

### D-004: The functional DSL is a separate language

The DSL has its own parser, type checker, intermediate representation, compiler, bytecode, deterministic VM, source maps, and version. It must never be implemented as unrestricted `eval`, `exec`, Python AST execution, or embedded Python.

### D-005: The language core remains deliberately small

The core contains immutable values, functions, application, `let`, conditionals, records, algebraic variants, exhaustive pattern matching, lists, and bounded library combinators. Tactical richness comes from composition, domain types, and standard-library functions.

### D-006: Programs are pure and emit intentions

A policy receives an immutable observation and explicit memory and returns new memory plus intentions. Programs cannot directly mutate entities, global state, files, clocks, random generators, or the renderer.

Conceptual entry point:

```text
step : Observation -> Memory -> (Memory, List Intent)
```

### D-007: The simulation is authoritative

The simulation validates, arbitrates, and resolves intentions. Returning `Fire target` does not guarantee a shot; weapon state, line of sight, timing, suppression, ammunition, and physical resolution determine the outcome.

### D-008: Missions run in real time

Kiwi evaluation and simulation continue on fixed ticks. The player may inspect, accelerate, slow, or pause only where the game mode explicitly permits it. The core fantasy is designing systems that operate under pressure, not issuing discrete turns.

### D-009: Direct control is prohibited

The player cannot normally select an operative and directly command movement, attacks, healing, or abilities. The player may transmit limited high-level signals that become typed inputs to the deployed policy.

### D-010: Deterministic replay is required

Given the same build, content versions, mission input, kiwi bytecode, command log, and seed, headless reruns must produce identical canonical state hashes at defined checkpoints.

Cross-version replay is not guaranteed unless a migration or compatibility runner is explicitly provided.

### D-011: The authoritative MVP simulation is project-owned

The MVP uses deterministic game-specific geometry, collision, projectile, cover, and movement systems. A third-party rigid-body engine is not authoritative in the MVP.

### D-012: Causal debugging is a product pillar

The system must preserve enough provenance to answer questions such as:

- Why did this operative choose this intention?
- Why was another intention rejected?
- Which observation values influenced the branch?
- Why did the intention fail during resolution?
- Which source expression contributed to this injury or objective failure?
- What changed between two runs?

### D-013: The UI consumes snapshots

The renderer reads immutable or read-only presentation snapshots and emits input commands. It does not mutate simulation entities.

### D-014: Headless operation is mandatory

The compiler, VM, simulation, replay verifier, trace queries, and content validation must run without importing or initialising pygame.

### D-015: The first vertical slice contains a bounded practice sequence

The first complete practice sequence contains `First Link`, `Terminal`, `Glasshouse`, and `Redline`. `Terminal` remains the central hostile-mainframe breach: a daemon bundle reaches payload data and exfiltrates before trace containment while incomplete ICE telemetry and flawed policy create an explainable failure. The other finite drills teach the same deterministic edit, preview, trace, and revision loop; they are not a procedural campaign.

### D-016: The visual terminal uses bitmap fonts

The source editor uses an original 8×12 or similarly readable bitmap font inspired by classic terminal typography. Creep may be evaluated for compact telemetry. Any bundled third-party font must have its licence and attribution recorded.

### D-017: No campaign complexity before the vertical slice

Persistent injuries, recruitment, relationships, broad progression, procedural campaigns, multiplayer, mod marketplaces, and large content sets remain out of scope until the vertical-slice loop is proven. Bounded skippable terminal cutscenes and codex lore are presentation content, not campaign systems.

### D-018: Language growth must preserve old programs intentionally

Every language release has a version. Breaking syntax or semantic changes require either migration tooling, explicit rejection with actionable diagnostics, or a documented decision that pre-release programs are not preserved.

### D-019: Milestone 4 emits language and bytecode version 2

Milestone 4 source and bytecode additions emit version `2`. The decoder retains
explicit version `1` support so existing bytecode is decoded with its original
semantics; version `1` artifacts are never reinterpreted as version `2`.

### D-020: Domain quantities are exact normalized rationals

DSL quantities carry a dimension tag and a normalized signed rational value.
Duration literals normalize to seconds, distance literals to metres, angle
literals to turns, and probability literals to fractions. Conversion to
integer simulation ticks or world subunits occurs only at the simulation
boundary under an explicit rounding rule.

### D-021: Milestone 4 domain operations use exact two-dimensional records

`Position` is the closed nominal record `Position { x: Distance, y: Distance }`
and `Vector` is `Vector { dx: Distance, dy: Distance }`. Their coordinate
operations are exact rational component arithmetic: `Position + Vector`,
`Position - Vector`, `Position - Position`, and `Vector +/- Vector`. Duration
and distance support `+` and `-`; duration, distance, and probability support
`<`, `<=`, `>`, and `>=`. Other combinations, including probability arithmetic,
are static errors. This is a language ABI within existing version 2; canonical
simulation subunits and elevation are defined separately by D-022.

### D-022: Canonical simulation geometry uses signed 64-bit millimetres

Authoritative planar coordinates, displacements, and distances use signed
64-bit integer millimetres. A canonical `WorldPosition` has `x`, `y`, and a
non-negative discrete `ElevationLayer`, which defaults to zero; a
`WorldVector` is planar and cannot silently cross elevation layers. At the
simulation boundary, an exact DSL `Distance` converts with 1 metre = 1,000
millimetres and nearest rounding with half ties away from zero. Arithmetic
fails on signed-64-bit overflow. Tick-duration conversion remains separate
from this spatial ABI and is selected with the fixed tick clock.

### D-023: Dynamic authority IDs are type-local signed 64-bit counters

Each dynamic authority ID family uses its own immutable counter, starts at one,
and allocates monotonically through the positive signed 64-bit range. Allocator
state is authoritative and allocation fails deterministically on exhaustion.
Content and reducer code must allocate in documented canonical order; no ID may
derive from Python object identity. Canonical byte encoding of allocator state
is defined with the later state-encoding task.

### D-024: Authority randomness uses versioned independent PCG32 streams

Authority uses no host random generator. Version 1 uses PCG XSH RR 64/32 with
fixed 64-bit multiplier and increment. A mission's unsigned 64-bit root seed
derives independently seeded named streams through fixed SplitMix64 arithmetic,
so a draw in one stream cannot shift another. The initial API emits one raw
uniform unsigned 32-bit value and a record containing stream, raw draw index,
range, result, and stable purpose label. Derived distributions require their
own named, bounded conversion policy before use in authority.

### D-025: Canonical mission state is versioned binary and BLAKE2b-256 hashed

Canonical mission state uses the project-owned `KWI-STATE\0` binary format,
version `2`, with fixed-width big-endian scalars and ordered length-prefixed
collections. It serialises all currently materialised authority state: mission
tick and phase, entity geometry, per-entity data-only policy memory, ID
allocation, scheduled events, root seed, and named random-stream state. The
state hash is a 32-byte BLAKE2b digest of those exact bytes. Version `1` and
unknown versions are rejected rather than reinterpreted: policy-memory support
is an intentional breaking change with no compatibility decoder or migration.
Later evolution requires a new version and explicit migration or compatibility
policy. Its current format version is superseded by D-028.

### D-026: Early kernel fixtures use strict versioned JSON

Milestone 5 kernel fixtures use UTF-8 JSON with format identifier
`kiwi-kernel-fixture` and version `1`. JSON needs no dependency beyond the
standard library and remains inspectable in tests. The loader rejects duplicate
or unknown fields and converts content-ID keyed entity maps into explicit sorted
immutable values before dynamic authority ID allocation. This narrow fixture
format is separate from the later full mission schema; incompatible evolution
requires a new version and migration or compatibility policy.

### D-027: Observation ABI begins with owner-visible state only

Observation ABI version `1` provides each policy only its own entity ID, planar
position, and current tick. It excludes elevation, other entities, contacts,
messages, signals, objectives, and presentation state until those fields have
defined authority semantics and provenance. The simulation converts this data to
closed immutable DSL records; ABI changes require explicit policy compatibility
handling.

### D-028: Policy versions require canonical-state version 3

Milestone 6 adds an entity-ID-ordered deployed-policy version store to
authority state. Each version is the 32-byte BLAKE2b digest of canonical
`KWI-BC\0` bytes plus the selected entry `FunctionId`, domain-separated as
`KWI-POLICY-VERSION\0`. It identifies the exact compiled entry that supplied an
entity's persisted memory and future policy input. `KWI-STATE\0` therefore uses
version `3`; versions `1` and `2` are rejected with no compatibility decoder or
migration because the project remains in development. Its current format version
is superseded by D-030.

### D-029: Operatives use fixed 350 millimetre disc footprints

Milestone 7 represents each operative as a closed planar disc centred at its
`WorldPosition`, with a fixed 350 millimetre radius. Boundary contact is a
collision; elevation is a separate discrete layer. This gives movement,
clearance, separation, and later projectile tests one integer-only geometry
primitive without committing authority to a third-party physics engine. Stance,
injury, equipment, and rendering do not change the footprint initially.

### D-030: Maps use closed axis-aligned obstacle rectangles

Milestone 7 represents a tactical map as an optional non-empty closed planar
`WorldRectangle` and its static obstacles as an immutable tuple of closed,
non-empty axis-aligned rectangles in ascending `ObstacleId` order. Every
obstacle lies wholly within its map and has a discrete elevation layer; map
bounds contain entity centres, while disc clearance and collision are movement
concerns. `KWI-STATE\0` therefore uses version `4`; versions `1`, `2`, and `3`
are rejected with no compatibility decoder or migration because development
state remains disposable. Its current format version is superseded by D-033.

### D-031: Paths retain exact endpoint-inclusive waypoints

Milestone 7 represents a route request as one immutable map and same-elevation
start and goal positions. Its resolved path is an immutable ordered tuple of
exact `WorldPosition` waypoints including both endpoints; one waypoint denotes
an already-arrived request and adjacent duplicate waypoints are invalid.
Precondition validation reports stable structured failures before routing, and
the selected pathfinding algorithm separately establishes obstacle clearance.

### D-032: Routing uses a bounded deterministic visibility graph

Milestone 7 resolves paths with Dijkstra over same-elevation start, goal, and
obstacle-corner candidates. Obstacles are conservatively inflated to the
operative's 350 millimetre axis-aligned clearance; candidate corners sit one
integer millimetre beyond that boundary. Routing examines at most 64 relevant
obstacles, uses exact Manhattan edge costs, and selects equal-cost paths by the
lexicographic ordered waypoint coordinates. This retains deterministic integer
behaviour without a third-party navigation dependency.

### D-033: Movement advances dominant-axis progress at 100 millimetres per tick

An active movement action records its entity, endpoint-inclusive path, next
waypoint index, and non-negative dominant-axis segment progress. Each active
tick advances at most 100 millimetres of that progress; planar coordinates use
integer nearest rounding with ties away from zero. Reaching an intermediate
waypoint resets progress for the next segment, and reaching the final waypoint
removes the action. `KWI-STATE\0` therefore uses version `5`; versions `1`
through `4` are rejected with no compatibility decoder or migration because
development state remains disposable. Collision and resulting events remain
separate movement phases. Its current format version is superseded by D-037.

### D-034: Movement collision uses exact swept discs and entity-ID priority

Each attempted movement segment checks the operative's closed 350 millimetre
disc against the closed map boundary and same-elevation obstacle rectangles
using integer squared-distance comparisons. Same-elevation operative discs may
not contact or overlap: their centre distance must exceed 700 millimetres. The
resolver processes entity IDs ascending; a candidate checks accepted lower-ID
trajectories and unprocessed entities at their current positions. A blocked
candidate retains its prior action progress. This is a bounded deterministic
avoidance rule, not crowd-dynamics simulation.

### D-035: Movement resolutions emit one structured authority event

Every active movement action produces exactly one canonical event each active
tick: progress, block, or arrival. The event retains the entity ID, tick,
start, attempted, and result positions; block events additionally retain the
stable map-collision or operative-separation reason. Event IDs allocate after
earlier same-tick command, schedule, and policy events in reducer phase order.

### D-036: Bundle BigBlue Terminal as the initial bitmap font

Milestone 7 bundles the BigBlueTerm437 Nerd Font Mono release v3.4.0 at its
native 8x12 pixel height. The user approved its CC-BY-SA-4.0 terms. The exact
licence, attribution, release URL, and SHA-256 remain in the packaged render
asset manifest; rendering disables antialiasing and only applies integer
unfiltered scaling. No font asset is authoritative.

### D-037: MoveToward activates source-linked canonical routes

`MoveToward { target: Position }` is the first executable policy intention.
Its exact `Distance` coordinates convert to canonical millimetres at the
simulation boundary and inherit the issuing entity's current elevation layer.
The compiler declares the source-linked `move_toward` capability. After
locomotion arbitration, a selected request either starts a bounded canonical
route or records its structured query or search failure. A request for the
currently active route target retains that action; a new successful target
replaces it.

Route-start events parent the selected intention event. Active movement actions
retain that route-start event ID, so every subsequent progress, block, or
arrival event parents it. `KWI-STATE\0` therefore uses version `6`, which adds
the optional route-origin event ID to each movement action. Versions `1`
through `5` are rejected with no compatibility decoder or migration because
development state remains disposable.

### D-038: Initial visibility is exact same-layer map line of sight

Milestone 8 starts perception with a pure query from one canonical observer
position to one canonical target position over the immutable map. Different
elevation layers are not visible. Same-layer closed obstacle rectangles occlude
when the closed centre-to-centre segment touches them, including endpoint and
corner contact. When several obstacles occlude, the ascending `ObstacleId`
order selects the retained blocker. Missing maps and out-of-bounds endpoints
return structured `V001` through `V003` failures. Field of view, contacts, and
visible-geometry observations remain separate tasks.

### D-039: Sensors use inclusive squared-distance ranges

Milestone 8 represents a sensor range as one non-negative canonical millimetre
radius. Range checks compare integer squared planar distance and include the
exact boundary; out-of-range precedes elevation and obstacle evaluation in a
visibility result. The initial visible-geometry projection contains the
same-layer static obstacles whose nearest closed-rectangle point is in range,
ordered by `ObstacleId`; it does not use obstacle occlusion to hide geometry.
These pure values are not added to policy observation ABI version `1` until the
contact and observation-provenance tasks define the complete exposure model.

### D-040: Contacts are owner-local uncertain estimates

Milestone 8 contact values retain a local `ContactId`, owner entity ID,
estimated canonical position, non-negative millimetre uncertainty radius,
inclusive 0–10,000 basis-point confidence, and last observed tick. Age is the
exact non-negative difference from a supplied current tick. Contacts contain no
hidden target entity ID, true state, evidence IDs, classification, or velocity;
those require their later lifecycle and provenance models.

### D-041: Contact lifecycle is explicit, deterministic, and identity-blind

Contacts are stored canonically by `(owner entity ID, contact ID)` with the
latest lifecycle tick. Visibility-associated sightings create contacts in
canonical sighting order or replace an explicit existing owner-local contact;
no true target entity ID is retained for automatic association. Active reducer
ticks apply a fixed 100 basis-point confidence loss and 100 millimetre
uncertainty growth per elapsed tick. Contacts are removed at zero confidence,
including an explicit zero-confidence update. `KWI-STATE\0` therefore uses
version `7`, which serialises this store and lifecycle tick. Versions `1`
through `6` are rejected with no migration because development state remains
disposable.

### D-042: Contact provenance is complete per policy-relevant field

Every contact stores immutable evidence mappings for estimated position,
uncertainty radius, confidence, and last-observed tick. Each mapping contains
one to 64 unique ascending authority `EventId` values. Direct sensor evidence
and later relayed-message evidence may share a mapping; automatic lifecycle
decay preserves the mappings. The state validator rejects evidence IDs not yet
allocated, preventing references to future events. `KWI-STATE\0` therefore uses
version `8`; versions `1` through `7` are rejected without migration because
development state remains disposable.

### D-043: Messages are typed radio records in observation ABI version 2

The initial message value has a `MessageId`, sender and recipient entity IDs,
typed `radio` channel, persistable nominal-record payload, send/delivery/expiry
ticks, non-negative sequence, and one to 64 ascending provenance event IDs.
Inbox observations order messages by `(delivery tick, sender entity ID,
sequence, message ID)` and expose only delivered, unexpired messages addressed
to their owner. Observation ABI version `2` adds an immutable
`InboxObservation { messages }` field; the current builder supplies it empty
until delivery state is implemented. This supersedes D-027. No compatibility
adapter is retained because development policy artifacts remain disposable.

### D-044: Initial messages deliver on the next authoritative tick

`send_message` allocates a message ID and global sequence, records delivery at
exactly `send tick + 1`, and retains the message through its inclusive expiry
tick. The canonical ledger is ordered by `(delivery tick, sender entity ID,
sequence, message ID)`; active reduction discards expired entries before policy
evaluation, and each policy receives only its addressed delivered messages.
`KWI-STATE\0` therefore uses version `9`; versions `1` through `8` are rejected
without migration because development state remains disposable.

### D-045: Signals are current-tick ABI version 3 values

An active-mission `IssueSignal` command is accepted in canonical command order
and records its signal name, tick, command sequence, source, optional entity
target, and issuing `SignalIssued` event ID. A squad signal is visible to every
entity; an entity-targeted signal is visible only to that entity. Signals are
visible only during their exact tick and are discarded before the following
tick's policy evaluation. Observation ABI version `3` adds
`signals: List<Signal>`, with each closed DSL value shaped as
`Signal { name, tick }`. The authoritative records retain command and event
provenance for later causal linking. `KWI-STATE\0` therefore uses version `10`;
versions `1` through `9` are rejected without migration because development
state remains disposable.

### D-046: Message events preserve send-to-delivery causality

Message allocation reserves an authority `send_event_id` after all ordered
source-provenance IDs. `MessageSent` uses that ID and exactly those source IDs
as causal parents. The active reducer emits `MessageDelivered` events before
policy evaluation for delivery-tick messages in canonical ledger order; each
delivery event has only its message's send event as parent. The message ledger
retains the send ID, so later observation provenance can resolve an unbroken
source-to-send-to-delivery chain without presentation state. `KWI-STATE\0`
therefore uses version `11`; versions `1` through `10` are rejected without
migration because development state remains disposable.

### D-047: Observation ABI version 4 exposes one nearest owner-local contact

Observation ABI version `4` adds
`nearest_contact: Option<Contact>` to the closed immutable `Observation`
record. The builder selects only contacts owned by the observing entity, using
exact planar squared distance from its current position and ascending
`ContactId` as the equal-distance tie-break. The exposed `Contact` record has
`age_ticks`, `confidence_basis_points`, `contact_id`, `estimated_position`, and
`uncertainty_radius`; it excludes owner identity, elevation, true target state,
and provenance IDs. The authority-side observation retains the selected contact
estimate and its field evidence for later trace construction.

A delivered `ContactReport` is a typed inbox payload only. It never creates,
updates, or associates a `ContactStore` entry implicitly: message-to-contact
merging needs a later explicit identity and provenance model. This change does
not alter canonical state format version `11`. No ABI compatibility adapter is
retained because deployed policy artifacts remain development-only.

### D-048: Cover uses canonically directed slotted segments

A cover feature is a `CoverSegment` with a positive `CoverId`, two distinct
same-elevation endpoints ordered lexically by planar `(x, y)`, a `low` or
`high` height class, and inclusive 0–10,000 basis-point integrity. The endpoint
order defines the segment direction, so `left` and `right` are stable sides
rather than content-author-dependent labels. Each segment has one through 16
contiguous-indexed `CoverSlot` values; a slot has one same-elevation standing
position and side. Slot positions are unique within their segment, but their
precise geometric relationship to the edge is not constrained until cover
occupancy resolution is defined.

Cover segments reside in a `CoverId`-ordered authoritative store. Reservation,
occupancy, exposure, and integrity damage are deliberately separate later
rules. `KWI-STATE\0` therefore uses version `12`, serialising the cover store
before contacts. Versions `1` through `11` are rejected with no migration or
compatibility decoder because development state remains disposable. Its current
format version is superseded by D-051.

### D-049: Observation ABI version 5 projects range-visible cover

Observation ABI version `5` adds `visible_covers: List<Cover>`. Until
per-entity sensor equipment exists, the builder uses one fixed 10,000 millimetre
sensor range. A cover is visible when it shares the observer's elevation and
the exact minimum planar distance to its segment is within that inclusive range;
the projection remains `CoverId` ordered. As with initial visible geometry,
obstacles do not occlude static cover projection. The closed `Cover` value
contains its ID, endpoints, height tag, integrity basis points, and slotted
positions/sides. It exposes neither occupancy nor hidden cover state. This ABI
change does not alter canonical state format version `12`.

### D-050: Initial cover exposure is side, height, and integrity based

`estimate_cover_exposure` accepts only a cover segment, one of its slots, and a
contact estimate. It derives the contact's side from the directed segment and
the estimate position; same-side, collinear, or cross-elevation contacts have
full 10,000-basis-point exposure. A slot is protected only from the opposite
side: low cover protects 5,000 basis points and high cover 7,500, each scaled
down by integer-floor integrity. This is an estimate, not hidden-world line of
fire or occupancy resolution.

### D-051: Cover slots use persistent deterministic reservations

Each cover slot has at most one persistent reservation and each entity holds at
most one reservation. An entry contains its `CoverId`, slot index, owner
`EntityId`, and the selected `IntentionId` that last granted it; entries are
ordered by `(cover ID, slot index)`. A request must name an existing slot and is
resolved in ascending `(priority, entity ID, intention ID)` order, where a lower
priority integer wins. A successful request replaces that entity's prior
reservation. A failed reassignment leaves the prior reservation intact. A claim
blocked by an existing holder reports `slot_reserved`; one blocked by an earlier
claim in the same batch reports `slot_contested` and names the winning intention.

This reservation is authority state, not player-visible observation or physical
occupancy. `KWI-STATE\0` version `13` serialises the reservation store after
cover geometry and before contacts. Versions `1` through `12` are rejected with
no migration or compatibility decoder because development state remains
disposable.

### D-052: TakeCover selects an eligible requested-side reservation

`TakeCover` is the closed runtime record `{ cover_id: Int, side: String }`. Its
validator accepts only a positive `CoverId` and the exact `left` or `right` side
tags, reports stable `I006` and `I007` failures otherwise, and requires the
source-linked `take_cover` capability. After locomotion arbitration, a selected
request retains its existing same-cover same-side slot when present; otherwise
it chooses the first unreserved matching-side slot in ascending slot-index order
before applying D-051 contention. Each outcome emits a source-linked canonical
grant or rejection event parented by the selected intention. Reservation does
not imply movement, occupancy, or player-visible hidden state. This consumes the
already-versioned D-051 reservation field and does not change `KWI-STATE\0`
version `13`.

### D-053: Cover helpers use only observed geometry and exact deterministic ranks

The closed `Cover` standard-library module adds four direct-only bytecode-v2
intrinsics: `exposure(Cover, CoverSlot, Contact) -> Int`,
`route_cost(Position, CoverSlot) -> Distance`,
`nearest_safe(List<Cover>, Position, Contact) -> Option<TakeCover>`, and
`seek(Int, String) -> TakeCover`. Their records must exactly match the
owner-visible ABI layouts. `exposure` returns the same 0–10,000 side, height,
and integrity estimate as D-050. `route_cost` is the exact planar Manhattan
distance proxy; it does not query map, routes, occupancy, reservations, or
hidden state. `nearest_safe` evaluates every supplied slot and selects by
ascending `(exposure, route cost, CoverId, slot index)`, returning `None` only
when there are no supplied slots; its supplied cover and slot lists retain their
observed ascending `CoverId` and slot-index order. `seek` retains its arguments for the normal
TakeCover validator, including `I006`/`I007` failures. These bounded intrinsics
charge deterministic instruction and allocation budgets. Their existing
one-byte `PUSH_INTRINSIC` representation gains tags `7` through `10`; prior
version-2 bytes retain their meanings, so no language, bytecode, or state
version changes.

### D-054: Cover selection traces are optional VM-derived semantic records

`run_vm(..., capture_cover_selection_trace=True)` retains one in-memory
`CoverSelectionTrace` for each successful `Cover.nearest_safe` call. It keeps
the intrinsic call's source-map entry and candidate records in final rank order:
the selected slot first, followed by rejected slots with their exact exposure,
Manhattan route cost, and first losing rank component. Trace capture reads only
the already-supplied immutable values and does not allocate authority IDs,
alter VM values or faults, affect state hashes, or change bytecode/state
formats. It is deliberately not the durable generic trace model; later trace
milestones own trace levels, persistence, and cross-phase graph construction.

### D-055: Cover presentation derives occupancy from current positions, not reservations

`PresentationSnapshot` copies `CoverId`-ordered cover segments with their
height, integrity, and ordered slots. A slot's optional display occupant is the
lowest-ID operative whose current exact same-elevation position equals its slot
position when the snapshot is built. It is a copied read-model annotation only:
it does not expose cover reservations, predict movement, allocate IDs, change
state hashes, or imply that the later authoritative occupancy phase exists.
The renderer may derive contact-facing threat rays from already-projected local
contact estimates; it receives no true target identity or renderer-writable
authority reference.

### D-056: Weapons use neutral magazines and sparse target-free aim quality

Each equipped weapon has an allocated `WeaponId`, an owning `EntityId`, and
`Ammunition { capacity, loaded_rounds }`; capacity is one through 65,535 and
loaded rounds are zero through capacity. The initial authority model deliberately
does not assign weapon classes, damage, projectile properties, or fiction. Aim
is a sparse entity-ID-ordered store of nonzero 1–10,000 basis-point quality;
an absent entry is canonical zero and carries no target. The compiler records a
source-linked `fire` capability requirement for a `Fire` record, but runtime
fire-intention validation and weapon ownership enforcement remain M10 #15.

`KWI-STATE\0` version `14` serialises the weapon store and aim store after
cover reservations and before contacts, plus the appended weapon ID allocator
counter. Versions `1` through `13` are rejected with no migration because
development state is disposable.

### D-057: Aim rewards holding position and suppression sets a visible ceiling

Suppression is a sparse entity-ID-ordered store of nonzero 1–10,000 basis
points; absence is canonical zero. During an active tick, aim progresses after
movement resolution and before the clock advances. A stationary or blocked
entity gains `floor((tick + 1) * 10,000 / rate) - floor(tick * 10,000 / rate)`
basis points, reaching full aim in exactly one real-time second at every
supported fixed rate. An entity whose resolved position changed resets to zero.

Suppression `S` sets a linear aim ceiling of `10,000 - S`; the update clamps
aim to that ceiling immediately. `SelfObservation` ABI version `6` exposes
current aim, suppression, and the calculated ceiling so policy and later trace
code can distinguish incomplete preparation from suppression. This task adds no
suppression source or decay, target selection, Aim/Fire intention, projectile,
or movement-speed penalty.

`KWI-STATE\0` version `15` serialises suppression after aim state and before
contacts. Versions `1` through `14` are rejected with no migration because
development state is disposable.

### D-058: Projectiles are owner-bound point states with explicit origin and lifetime

A live projectile has an allocated `ProjectileId`, owner `EntityId`, allocated
source `IntentionId`, exact position and elevation, nonzero integer
millimetres-per-tick `WorldVector`, and a positive bounded remaining lifetime.
`ProjectileStore` is strictly projectile-ID ordered. This commits only to a
point representation: radius, damage profile, collision, advancement,
expiration, ammunition consumption, and firing validation remain their later
M10 tasks. Projectiles may be outside map bounds because collision resolution
has not yet defined boundary removal.

`KWI-STATE\0` version `16` serialises projectile state after suppression and
before contacts. Versions `1` through `15` are rejected with no migration
because development state is disposable.

### D-059: Projectile sweeps select one canonical earliest collision

`sweep_projectiles` is a pure projectile-ID-ordered query over each live
point projectile's current position and one exact per-tick endpoint. It tests
only equal-elevation static obstacle rectangles, cover segments, and operative
350-millimetre discs. Map bounds are not collision candidates: D-058 permits
projectiles outside them until a later boundary-removal rule exists.

For each candidate, the earliest time is the smallest of `2^32` canonical
subticks whose rounded integer-millimetre prefix segment intersects it. Prefix
positions use the existing nearest, ties-away-from-zero conversion. This
bounded integer query prevents tunnelling without float geometry or
wall-clock-dependent precision. Equal subticks order collision classes as
obstacle, cover, operative, then the target's ascending stable ID.

The sweep query does not mutate projectile position or lifetime, remove a
projectile, emit an event, damage an operative, or alter cover. Those impact
effects remain a later M10 phase consuming this selected collision.

### D-060: Projectile impacts consume collisions and expire after final travel

After movement and aim resolution, every live projectile receives exactly one
ID-ordered swept-impact resolution. A selected obstacle, cover, or operative
collision consumes the projectile at its collision point and retains a
transient impact result containing the original projectile and collision for
the later damage and event phases. A projectile with no collision advances to
its exact endpoint and loses one remaining tick; one with one remaining tick
travels its final unobstructed segment then expires. This does not damage an
operative, change cover integrity, suppress entities, or emit events; those
effects remain dedicated later M10 phases. It adds no durable state field or
canonical-format revision.

### D-061: Operative damage uses a small deterministic condition track

Each entity has an implicit default `OperativeCondition` of health `3`, one
consumable protection point, and `stabilized = false`. The condition store is
sparse and entity-ID ordered: non-default values carry current health
`0`–`3`, protection `0`–`1`, and stabilization. An operative projectile impact
does exactly one damage point. Protection absorbs it first; remaining damage
reduces health without random variation or hit-location rules. Health bands
are `3` none, `2` minor, `1` severe, and `0` incapacitated. A health-damaging
impact clears stabilization.

Impacts resolve in projectile-ID order. Incapacitation removes a live movement
action and cover reservation, and no policy is invoked for that entity, so it
cannot initiate non-medical actions. The medical phase owns any later
stabilization or recovery semantics. Obstacle and cover impacts do not enter
this damage phase. The structured damage result retains its source projectile
impact for later event and causal-edge emission.

`KWI-STATE\0` version `17` serializes sparse operative conditions after live
projectiles and before contacts. Versions `1` through `16` are rejected with
no migration because development state is disposable. `SelfObservation` ABI
version `7` adds owner-visible health, protection, derived injury severity,
incapacitation, and stabilization.

### D-062: Projectile paths and impacts cause bounded, decaying suppression

Every active tick first reduces each entity's retained suppression by `500`
basis points, to a minimum of zero. Each pre-impact projectile then contributes
`1,500` basis points to every same-elevation non-owner entity within an exact
two-metre closed radius of its travelled segment. A direct operative collision
does not also count as a near miss for that target. Every collision contributes
`2,500` basis points to every same-elevation non-owner entity within an exact
three-metre closed radius of its impact point. Contributions stack in
projectile-ID then source-kind order and clamp the resulting sparse
suppression value at `10,000`.

The suppression phase runs after projectile impacts and damage. It immediately
clamps current aim to the new `10,000 - suppression` ceiling, so a same-tick
shot or impact cannot leave illegal aim quality. Each transient contribution
retains the source projectile and, where applicable, the impact for later
event and causal-edge emission. This changes no durable state layout or
observation ABI: the existing sparse suppression field and owner-visible
observation value remain authoritative.

### D-063: Aim reserves the weapon channel and fire uses generic exact shots

`Aim {}` is a source-linked `aim` capability action with no target payload. It
occupies the `weapon` arbitration channel while retaining D-057's automatic
stationary aim progression. `Fire { target: Position, weapon_id: Int }`
requires the source-linked `fire` capability, a positive weapon ID, and an
exact planar target position from the policy's visible data.

After movement and automatic aim progression, each selected fire request
resolves in intention-ID order. It requires a non-incapacitated issuer, an
existing issuer-owned weapon with a loaded round, and a target distinct from
the issuer's current exact position. Success consumes one round, resets that
issuer's aim to zero, allocates a projectile, and retains the selected
intention as its source. Rejections are structured values for later event
emission. A generic projectile starts at the issuer, lasts `30` ticks, and
uses a componentwise nearest-integer approximation of a 1,000-millimetre
Euclidean direction vector with exact integer comparisons. It uses no
dispersion or random draw. Projectile sweeps exclude their owner but retain
all other operative collisions.

This changes no durable state layout or observation ABI. `KWI-STATE\0` version
`17` continues to encode the resulting existing magazine, aim, and projectile
state.

### D-064: Combat events retain phase results with bounded causal parents

Selected Fire outcomes emit `fire_fired` or `fire_rejected` records in
intention-ID order, each parented by the corresponding selected-intention
event. Every live projectile emits exactly one projectile-ID-ordered outcome:
advance, expiry, or impact. Projectile outcomes retain the existing exact
transient resolution; they do not introduce a new event-reference field before
the dedicated provenance work.

Each operative impact emits a damage event parented by its projectile impact.
It emits an injury event parented by that damage only when the stable injury
severity changes. Each nonzero suppression change emits an entity-ID-ordered
event whose parents are unique current-tick projectile outcomes from its
retained contributions; decay-only changes have no physical parents. These
events use the existing event-ID allocator and do not change `KWI-STATE\0`
version `17` or the observation ABI.

### D-065: Projectiles retain complete durable Fire provenance

Every live projectile retains the full immutable `IntentionOrigin` of the Fire
request that created it: intention ID, issuer, policy invocation ID, expression
ID, source file/span, policy-list index, and creation tick. The projectile owner
must match the origin issuer. Impact and damage values expose that same origin,
and injury events retain it through their damage resolution; no causal lookup by
reused object identity is required.

`KWI-STATE\0` version `18` serializes this provenance in every live projectile
after its owner ID and before physical fields. Versions `1` through `17` are
rejected with no migration because development state is disposable. This adds no
observation field or renderer dependency.

### D-066: Causal traces start as strict run-local version-one packets

`KWI-TRACE\0` version `1` is a bounded canonical UTF-8 JSON packet holding one
immutable trace graph tied to a 32-byte canonical run-state hash. It contains a
declared summary, decision, or full level; node-ID-ordered typed policy,
expression, observation, intention, resolution, world-event, and consequence
records; and edge-ID-ordered typed causal links. Values are closed summaries,
typed IDs, digests, source spans, and explicit nullable fields: neither Python
object serialisation nor authoritative-state references are permitted.

Version `1` rejects version `0`, unknown versions, malformed or duplicate
fields, oversized packets, and noncanonical encodings. It intentionally omits
chunking, interning, queries, and replay packaging; later trace milestones own
those compatible extensions. Capture applies a non-authoritative Summary,
Decision, or Full policy plus optional trailing-tick and bounded record/edge
retention before constructing a packet. Policy-lifecycle capture projects
canonical validation and arbitration events into decision-level records, while
headless-run capture adds canonical world events, parent edges, and current
injury consequences only after the matching authority state is hashed. Trace
capture and trace hashing do not participate in canonical mission state.

### D-067: Replays use strict version-one packets without migration

`KWI-RUN\0` version `1` is a bounded canonical UTF-8 JSON replay packet for
one headless run. It retains build and simulation identifiers, mission and
execution-policy hashes, a self-verifying initial authority snapshot, matching
root seed, tick rate, canonically ordered external commands, and checkpoint
hashes. Policy hashes identify the bindings to execute and their entity IDs
must belong to the initial snapshot; they are intentionally independent of a
snapshot's prior deployment history. The initial snapshot is the first
checkpoint; its state and seed must match the manifest, so redundant replay
metadata cannot silently describe a different run.

Only version `1` is accepted. Version `0`, every future or historical version,
and all migration paths are rejected. This user-approved development policy
matches D-010: cross-version replay requires a separately approved migration or
compatibility runner. Embedded seek snapshots, trace references, content
resolution, and later comparison detail remain deferred to their owning
milestones. A matching `.dseek` sidecar enables verifier failures to include
the first canonical-state field path and expected/reconstructed values at the
first divergent checkpoint.

### D-068: Periodic replay snapshots use a separate strict sidecar

`KWI-SEEK\0` version `1` is an optional bounded binary `.dseek` sidecar. It
contains the BLAKE2b-256 identity of one canonical `.drun` packet followed by
all of that replay's checkpoint snapshots in ascending tick order. Every
snapshot remains independently self-verifying through its canonical state hash,
and its tick/hash must exactly match the corresponding replay checkpoint.

Seeking rejects replay-hash, checkpoint, policy-version, snapshot, and target
range mismatches before it restores the nearest preceding snapshot and
headlessly advances the remaining fixed ticks. `.dseek` preserves the
user-approved strict `.drun` v1 policy: it introduces no `.drun` field,
migration, or compatibility runner. Only sidecar version `1` is accepted.

### D-069: Historical source uses replay-bound strict sidecars

`KWI-SOURCE\0` version `1` is an optional bounded binary `.dsrc` sidecar. It
contains the BLAKE2b-256 identity of one canonical `.drun`, exact UTF-8 source
text with its source-language version and content hash, and each deployed
entity's selected entry function plus canonical bytecode. The bytecode's
existing source map is retained without projection; source text reconstructs
the line index needed to navigate each span. Every source-map span must be
valid against its retained text, and retained sources must exactly match the
bytecode headers.

Consumers require both the replay hash and entity-ID-ordered policy-version
manifest to match before resolving historical source. Only sidecar version `1`
is accepted. `.dsrc` introduces no `.drun` field, migration, compatibility
runner, or authority dependency, preserving the user-approved strict replay
v1 policy.

### D-070: Run comparison requires one exact non-policy baseline

Before comparing two replay outcomes, Kiwi requires equal application build,
simulation version, mission hash, initial authority snapshot, root seed, fixed
tick rate, and canonical command log. Each mismatch is reported as a stable
structured compatibility failure in a fixed order. This does not claim
cross-version replay execution: unequal builds or simulation versions are not
comparable.

Entity-ID-ordered policy-version manifest changes are instead explicit
comparison output. Additions, removals, and substitutions preserve their
entity ID and old/new version where present. This permits controlled policy
experiments without weakening the replay v1 migration policy.

### D-071: First policy differences use logical evaluation and intention keys

Compatible headless runs compare policy evaluations in ascending `(tick, entity
ID)` order. Emitted intentions compare in ascending `(tick, issuer entity ID,
policy order)` order. The comparison returns the first added, removed, or
changed record for each stream, retaining the exact canonical events for
inspection.

Allocation-only policy invocation and intention IDs are ignored when comparing
emitted intention semantics. Issuer, source expression and span, policy order,
creation tick, intention kind, and validated payload remain significant. This
prevents a prior allocation shift from being mistaken for a policy choice.

### D-072: Changed consequences use logical causal keys

Retained `ConsequenceTrace` records compare by ascending `(tick, consequence
kind, subject entity IDs)`. The comparison returns all added, removed, and
changed records and retains their exact expected and actual trace values for
downstream causal inspection. Trace-node and authority-event IDs are
run-local allocation detail and do not cause a changed consequence; the
human-readable closed summary remains significant.

### D-073: Terminal uses one scheduled extraction lockdown

Terminal applies time pressure through a one-shot lockdown rather than dynamic
reinforcement spawning, avoiding hidden entity or policy-binding changes during
a run. The application adapter converts its fixed 90-second delay to the
mission's immutable tick rate and schedules one `LOCKDOWN` event. At its exact
tick, authority emits the existing scheduled-trigger event followed by a
parented lockdown-activation event, persists its activation tick and event ID,
and prevents later objective extraction. Only one pending or active lockdown is
valid. `KWI-STATE\0` version `20` serializes this state; versions `1` through
`19` remain unsupported because development state is disposable.

### D-074: Terminal challenge districts are explicit seeded content

Daily and Practice contracts construct a `ChallengeDefinition` before authority
is built. The definition retains a mode, challenge ID, unsigned seed, generator
version, and contract index. The generator produces a bounded 32×32 material
grid plus normal `MissionData`; a replay or save must retain the definition, not
depend on the host clock. Daily ISO-date selection is an application boundary, and
Practice seeds are player-supplied. Contract escalation derives the next seed
from the prior definition deterministically.

This is modular challenge content, not a procedural campaign: it creates no
hidden progression state, online service, or runtime dependency on pygame.

### D-075: Isometric assets and audio are presentation-only

The Terminal renderer may choose a rotatable isometric camera, texture-atlas
sprite, fixed-tick animation frame, palette, and event-ID-deduplicated audio
cue from copied snapshots and events. Those choices cannot change map geometry,
hit tests, random streams, policy evaluation, tick timing, or canonical state.
Missing art or audio falls back silently to renderer primitives.

### D-076: Local optimization records have no composite score

After a completed controlled run, the application may record a bounded local
result containing the run hash, explicit outcome, casualties, ticks, encoded
policy bytecode bytes, compiled VM instruction count, and policy evaluation count.
Histogram buckets are a deterministic presentation projection of those local
records. Results remain local by default and do not rank, upload, or alter the
authoritative replay.

## 2. Prohibited shortcuts

The following are not acceptable implementation substitutions:

- executing player code with Python `eval` or `exec`;
- using Python exceptions as ordinary DSL control flow;
- letting pygame objects leak into simulation state;
- using wall-clock time inside authoritative simulation;
- iterating unordered sets or dictionaries where order affects state;
- closing GitHub issues without verification evidence;
- weakening deterministic or provenance requirements to make a feature easier;
- recording only human-readable logs instead of structured causal data;
- implementing direct RTS controls as a temporary default that becomes permanent;
- building a general-purpose programming language before the game loop works.

## 3. Explicit non-goals for the MVP

- A complete XCOM-scale campaign
- Multiplayer or lockstep networking
- Hundreds of simultaneous agents
- A general 2D physics engine
- Soft-body, fluid, or destructible-material simulation
- A general-purpose IDE
- Arbitrary user plugins
- Python interoperability from the DSL
- User-defined foreign functions
- Unbounded recursion
- Runtime code generation
- Fully editable maps
- Workshop distribution services
- Console or mobile ports
- Photorealistic rendering

## 4. Open decisions

### O-001: Public project name

Resolved: the product title is `KIWI // Terminal`.

### O-002: Operative fiction

The squad may be human, synthetic, remote, or deliberately ambiguous. The mechanics must not depend on a final fiction during the prototype.

### O-003: Camera perspective

Resolved by D-075: the Terminal presentation uses a rotatable isometric
camera over the existing discrete elevation and explicit cover model. The
camera is excluded from authority.

### O-004: Exact static type system

The MVP requires checked primitive and domain types, records, variants, function signatures, and exhaustive matching. Full Hindley–Milner inference, row polymorphism, and higher-kinded abstractions are deferred.

### O-005: In-mission patching

The prototype may allow edits only between runs. Later versions may support bounded deployment windows, canary updates, propagation delays, and rollback. This must not be implemented before replay and causal attribution are stable.

### O-006: Persistent operative psychology

Stress, trauma, and traits may eventually affect observations or capabilities. They must be explicit data inputs, never hidden random overrides of code.

### O-007: Third-party physics usage

Non-authoritative debris or isolated mechanisms may later use Pymunk. The integration requires a written determinism boundary and tests proving that authoritative outcomes do not depend on nondeterministic external state.

### O-008: Static checker implementation depth

The first implementation may use explicit annotations at entry points and local inference for literals and expressions. Broader inference is a language-roadmap item rather than an MVP blocker.

### O-009: Distribution and packaging

Provisional M15 selection: the measured macOS prototype uses PyInstaller 6.21.0
to produce a one-directory arm64 application bundle with explicit render and
Terminal-content collection. Its command, result, and release gaps are recorded
in `PACKAGING.md`. The prototype does not alter authoritative code or make
PyInstaller a project dependency; Developer ID signing, notarization, licence
notices, release automation, and Linux/Windows evaluation remain open.

## 5. Decision rule for new features

A proposed feature should proceed only if it strengthens at least one of these:

1. Programming kiwi is expressive but learnable.
2. Autonomous squad behaviour creates meaningful tactical consequences.
3. The debugger makes those consequences legible.
4. Deterministic reruns support learning and comparison.
5. The feature is required by the current milestone.

If it primarily adds content volume, graphical polish, speculative extensibility, or conventional RTS functionality, defer it.
