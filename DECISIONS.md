# Design Decisions and Open Questions

## 1. Settled decisions

### D-001: The project is a programmable squad tactics game

It is not a tank game, salvage ecology, or general physics sandbox.

The structural inspiration is XCOM-like mission preparation and persistent squads, while tactical execution is autonomous and program-driven.

### D-002: The DSL is functional

Programs are pure functions over immutable observations and explicit memory.

### D-003: The language core remains deliberately small

No unrestricted loops, mutation, IO, or host-language escape.

### D-004: Programs emit intentions

The simulation, not the DSL, resolves outcomes.

### D-005: Missions run in real time

The canonical mission run is not a conventional pausable turn-based encounter.

### D-006: Live player control is limited to high-level signals

Signals become program inputs rather than direct commands.

### D-007: Causal debugging is a core product pillar

It must be implemented alongside simulation and language work, not added after the game is complete.

### D-008: Deterministic replay is required

Same-build deterministic reruns are a core requirement for debugging and testing.

### D-009: LÖVE 2D is the target engine

The game, editor, simulation, and tooling are implemented within a LÖVE-based desktop application, with a headless Lua runner where practical.

### D-010: The first vertical slice contains one mission

No campaign expansion before the full observe–program–execute–debug loop works.

### D-011: The terminal uses an original bitmap-font direction

The visual target draws from readable 8×12 terminal fonts and compact bitmap telemetry fonts. Third-party licences must be verified before shipping.

## 2. Explicit non-goals

- direct XCOM clone;
- general-purpose IDE;
- general-purpose functional language;
- unrestricted Lua execution;
- multiplayer in the MVP;
- procedural campaign in the MVP;
- high unit counts;
- tanks as mandatory framing;
- physics complexity without tactical relevance;
- AI-generated assets as the primary product value.

## 3. Open questions

### O-001: Working title

Current documentation uses “Doctrine.” Replace once a final name is chosen.

### O-002: Human soldiers, synthetic operatives, or ambiguous agents

This affects tone, injury treatment, visual style, and content rating. Keep systems neutral until a direction is chosen.

### O-003: Exact visual perspective

Candidates:

- strict top-down;
- oblique top-down;
- isometric-like 2D;
- side-view tactical cross-section.

Top-down is the safest for pathing, cover, and LÖVE implementation.

### O-004: Physics representation for operatives

Options:

- dynamic bodies;
- kinematic controller with physical projectiles;
- hybrid approach.

Recommended starting point: kinematic or controlled dynamic operative movement, physical projectiles, discrete destructible cover.

### O-005: Policy evaluation rate

Measure 10 Hz, 15 Hz, and 20 Hz. Physics can remain 60 Hz.

### O-006: Surface language syntax

The semantics are defined, but exact syntax can be prototyped for readability.

### O-007: Type-system depth

Start with first-order algebraic types and local inference. Defer advanced polymorphism, type classes, effects, and row polymorphism.

### O-008: Campaign permanence

Decide whether operatives can die permanently, become unavailable, or only suffer recoverable injury. This should follow tone and desired frustration level.

### O-009: In-mission hot deployment

The present design centres on pre-mission programming and post-mission debugging. Limited hot deployment may be added later through tactical communication windows, but it is not required for the first vertical slice.

### O-010: Modding format

Defer until core formats stabilise. Keep content data-driven now so mod support remains possible.

## 4. Decision rule for new features

A proposed feature should be rejected unless it materially improves at least one of:

- programmable tactical decisions;
- physically meaningful consequences;
- explainability;
- persistent squad preparation;
- deterministic iteration;
- onboarding into the functional DSL.
