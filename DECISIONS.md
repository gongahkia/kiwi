# Design Decisions and Open Questions

This file is the authoritative record of settled product and technical decisions. Any implementation change that contradicts a settled decision requires an explicit update here, a rationale, and corresponding specification changes.

## 1. Settled decisions

### D-001: The project is a programmable squad tactics game

The project uses an XCOM-like mission and squad-persistence structure but replaces direct turn-by-turn tactical control with programmable kiwi executed in real time.

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

### D-015: The first vertical slice contains one mission

The first complete mission is the working scenario `Glasshouse`: a small squad must enter a hostile structure, locate or recover an objective, and extract while incomplete information and flawed kiwi create an explainable failure.

### D-016: The visual terminal uses bitmap fonts

The source editor uses an original 8×12 or similarly readable bitmap font inspired by classic terminal typography. Creep may be evaluated for compact telemetry. Any bundled third-party font must have its licence and attribution recorded.

### D-017: No campaign complexity before the vertical slice

Persistent injuries, recruitment, relationships, broad progression, procedural campaigns, multiplayer, mod marketplaces, and large content sets remain out of scope until the vertical-slice loop is proven.

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

`Kiwi` is a working title only.

### O-002: Operative fiction

The squad may be human, synthetic, remote, or deliberately ambiguous. The mechanics must not depend on a final fiction during the prototype.

### O-003: Camera perspective

Candidates:

- top-down with abstracted elevation;
- oblique top-down with discrete floor levels;
- side-on tactical cross-section.

Default for implementation: top-down 2D with discrete elevation layers and explicit cover edges.

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

Candidate desktop packaging approaches must be benchmarked after the vertical slice. Do not prematurely couple architecture to a packager.

## 5. Decision rule for new features

A proposed feature should proceed only if it strengthens at least one of these:

1. Programming kiwi is expressive but learnable.
2. Autonomous squad behaviour creates meaningful tactical consequences.
3. The debugger makes those consequences legible.
4. Deterministic reruns support learning and comparison.
5. The feature is required by the current milestone.

If it primarily adds content volume, graphical polish, speculative extensibility, or conventional RTS functionality, defer it.
