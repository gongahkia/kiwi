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
