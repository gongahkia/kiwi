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
state remains disposable.

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

## 2. Prohibited shortcuts

The following are not acceptable implementation substitutions:

- executing player code with Python `eval` or `exec`;
- using Python exceptions as ordinary DSL control flow;
- letting pygame objects leak into simulation state;
- using wall-clock time inside authoritative simulation;
- iterating unordered sets or dictionaries where order affects state;
- marking TODO items complete without verification evidence;
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
