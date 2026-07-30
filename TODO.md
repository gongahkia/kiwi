# Implementation TODO

This plan is ordered to prove the product thesis as early as possible.

Do not parallelise large subsystems until their interfaces are tested. Each milestone has explicit exit criteria.

## Milestone 0 — Repository and engineering skeleton

### Goals

Create a reproducible, testable LÖVE project with headless test execution.

### Tasks

- [x] Initialise repository with `main.lua`, `conf.lua`, `src/`, `tests/`, `content/`, and `tools/`.
- [x] Pin the target LÖVE version and Lua runtime assumptions in the README.
- [x] Add a Makefile or task runner with `run`, `test`, `check`, and `headless` targets.
- [x] Select and configure a lightweight Lua test framework.
- [x] Add formatting and linting rules.
- [x] Add deterministic utility primitives:
  - [x] stable ordered map or sorted-key helper;
  - [x] stable ID allocator;
  - [x] deterministic PRNG wrapper;
  - [x] canonical serializer;
  - [x] hash wrapper.
- [x] Add CI for tests and content validation.
- [x] Create a minimal scene manager.
- [x] Create development logging with structured categories.

### Exit criteria

- `make test` runs headlessly.
- A minimal LÖVE window launches.
- Stable serialization and PRNG tests pass.
- Repository structure matches `ARCHITECTURE.md` or documents deviations.

## Milestone 1 — Tiny functional language parser

### Goals

Parse and display a minimal player-facing functional language.

### Language subset

- literals;
- identifiers;
- function declarations;
- application;
- `let`;
- `if`;
- tagged constructors;
- `case`;
- records;
- lists.

### Tasks

- [x] Define grammar in `docs/grammar.md` or parser comments.
- [x] Implement lexer with exact source spans.
- [ ] Implement parser with recoverable diagnostics.
- [ ] Define immutable AST representation.
- [ ] Implement AST pretty-printer.
- [ ] Add parser golden tests.
- [ ] Add fuzz tests for malformed input.
- [ ] Add a minimal source editor widget or load source from fixtures initially.

### Exit criteria

- Example policy source parses into a stable AST.
- Invalid source returns structured diagnostics with accurate spans.
- Parser cannot crash on arbitrary bounded input.

## Milestone 2 — Types and functional core

### Goals

Type-check the language and compile it into a small core representation.

### Tasks

- [ ] Implement primitive and domain type representations.
- [ ] Implement function types.
- [ ] Implement `Option`, `Result`, and selected domain unions.
- [ ] Implement name resolution and lexical scopes.
- [ ] Implement local type inference.
- [ ] Require explicit signatures for exported entry points.
- [ ] Implement pattern exhaustiveness checking.
- [ ] Implement capability manifest checking.
- [ ] Desugar pipelines and surface sugar into core AST.
- [ ] Add typed AST and core IR goldens.
- [ ] Implement domain-aware diagnostics.

### Exit criteria

- A sample `act` function type-checks.
- Missing pattern cases produce precise diagnostics.
- Invalid quantity types are rejected.
- The core IR contains no surface-only constructs.

## Milestone 3 — Bytecode and deterministic VM

### Goals

Execute typed programs safely with instruction and memory limits.

### Tasks

- [ ] Define bytecode instruction set.
- [ ] Define stable bytecode serialization format.
- [ ] Implement compiler from core IR to bytecode.
- [ ] Implement bytecode verifier.
- [ ] Implement deterministic VM.
- [ ] Implement bounded stack and heap.
- [ ] Implement instruction fuel.
- [ ] Implement stable value representation.
- [ ] Implement pure intrinsic table.
- [ ] Implement runtime error values.
- [ ] Implement source maps.
- [ ] Add VM safety and malformed-bytecode tests.
- [ ] Add deterministic execution tests.

### Exit criteria

- `act observation memory` returns new memory and intentions.
- Malformed bytecode is rejected before execution.
- Fuel exhaustion returns a safe error.
- No user program can access host Lua globals.
- Repeated execution with identical inputs returns identical outputs and trace IDs.

## Milestone 4 — Headless simulation kernel

### Goals

Create a deterministic tick-based world without rendering.

### Tasks

- [ ] Implement simulation clock using integer ticks.
- [ ] Implement stable entity IDs.
- [ ] Implement component stores.
- [ ] Define fixed system order.
- [ ] Implement queued structural changes.
- [ ] Implement tactical signal input stream.
- [ ] Implement basic mission objective state machine.
- [ ] Implement canonical events.
- [ ] Implement canonical state serialization and hashing.
- [ ] Implement snapshots.
- [ ] Implement headless runner.

### Exit criteria

- A trivial mission advances deterministically for 10,000 ticks.
- State hashes match across repeated local runs.
- A replay input stream can reproduce objective state.

## Milestone 5 — Operatives, observations, and intentions

### Goals

Connect VM programs to autonomous entities.

### Tasks

- [ ] Define operative component model.
- [ ] Define observation schemas.
- [ ] Implement observation builder.
- [ ] Implement explicit program memory.
- [ ] Define initial intent schemas.
- [ ] Implement intent validation.
- [ ] Implement conflict arbitration.
- [ ] Implement fallback policy after VM failure.
- [ ] Add observation and intent fixtures.
- [ ] Add tests proving hidden world state is not exposed.

### Exit criteria

- Four headless operatives run the same deployed policy independently.
- Programs receive only permitted observation data.
- Intent outcomes are explicit events.
- Runtime program failure produces fallback behaviour without host failure.

## Milestone 6 — Tactical movement and simple world rendering

### Goals

Render a small map and show autonomous movement.

### Tasks

- [ ] Integrate fixed-step `love.physics` world.
- [ ] Implement map geometry and collision categories.
- [ ] Implement operative movement controller.
- [ ] Implement simple pathfinding or navigation graph.
- [ ] Implement movement intent execution.
- [ ] Implement arrival, interruption, and failure outcomes.
- [ ] Render terrain, operatives, paths, and destinations.
- [ ] Add debug overlays for velocity and intended path.
- [ ] Add deterministic movement scenario tests.

### Exit criteria

- A policy can move operatives to regions.
- Two operatives can contend for a destination with deterministic arbitration.
- Rendering does not affect simulation results.

## Milestone 7 — Perception, contacts, and communication

### Goals

Introduce incomplete information and typed squad coordination.

### Tasks

- [ ] Implement line-of-sight queries.
- [ ] Implement sensor refresh schedule.
- [ ] Implement contact tracks with confidence and timestamps.
- [ ] Implement track decay.
- [ ] Implement typed message intent.
- [ ] Implement communication latency and range.
- [ ] Implement message delivery and failure events.
- [ ] Add overlays for vision, tracks, and communication links.
- [ ] Add tests for stale and relayed information.

### Exit criteria

- Operatives cannot act on hidden authoritative enemy positions.
- Delayed messages can produce divergent local decisions.
- Debug view distinguishes direct observation from relayed track.

## Milestone 8 — Cover, aiming, and projectiles

### Goals

Create the first inspectable combat interaction.

### Tasks

- [ ] Implement cover geometry and semantic cover points.
- [ ] Implement cover occupancy and reservation hooks.
- [ ] Implement aim state.
- [ ] Implement weapon readiness.
- [ ] Implement physical projectiles.
- [ ] Implement deterministic spread using scoped PRNG.
- [ ] Implement projectile collision events.
- [ ] Implement cover damage states.
- [ ] Implement operative damage.
- [ ] Implement `TakeCover`, `Aim`, and `Fire` intents.
- [ ] Add overlays for line of fire and cover protection.
- [ ] Add regression tests for projectile and cover interactions.

### Exit criteria

- A doctrine can select cover and fire at a perceived track.
- A shot’s trajectory and impact are replayable.
- Cover can alter or block the physical result.
- Every shot links back to a source evaluation and intent.

## Milestone 9 — Causal trace foundation

### Goals

Implement the minimum causal graph concurrently with gameplay.

### Tasks

- [ ] Assign stable IDs to observations, evaluations, expressions, intentions, and events.
- [ ] Record evaluation summaries.
- [ ] Record candidate behaviour selection.
- [ ] Record source spans and values.
- [ ] Link intentions to outcomes.
- [ ] Implement query: “Why was this behaviour selected?”
- [ ] Implement query: “Why did this intention fail?”
- [ ] Implement query: “What did this operative know?”
- [ ] Add golden explanation tests.

### Exit criteria

- A headless fixture produces a human-readable causal explanation.
- The explanation links to an exact source span.
- Program decision and physical outcome are represented separately.

## Milestone 10 — Replay and debugger UI

### Goals

Make causal analysis usable by a player.

### Tasks

- [ ] Implement replay file format.
- [ ] Implement periodic snapshots.
- [ ] Implement replay scrubber.
- [ ] Implement event timeline.
- [ ] Implement selected-operative event lane.
- [ ] Implement causal explanation panel.
- [ ] Implement historical source viewer.
- [ ] Synchronise replay, event, source, and explanation selections.
- [ ] Implement branch rerun from initial state with modified doctrine.
- [ ] Implement first-divergence comparison.

### Exit criteria

- The player can click an injury and trace it to a program decision.
- The source shown matches the deployed historical version.
- A revised doctrine can be rerun against the same initial seed.
- The UI reports the first divergent decision.

## Milestone 11 — Vertical-slice mission

### Goals

Build the complete “Glasshouse” scenario.

### Tasks

- [ ] Create authored map.
- [ ] Implement rescue or retrieval objective.
- [ ] Implement extraction.
- [ ] Implement two hostile archetypes.
- [ ] Implement basic enemy doctrine using the same or a restricted policy system.
- [ ] Implement medic and stabilisation.
- [ ] Implement suppression.
- [ ] Create initial flawed squad doctrine.
- [ ] Add player-editable target assignment and exposure logic.
- [ ] Add mission briefing and deployment screens.
- [ ] Add result screen and automatic debugger entry.
- [ ] Create tutorial prompts.
- [ ] Add vertical-slice smoke replay.

### Exit criteria

A tester can:

1. run the initial doctrine;
2. observe a meaningful failure;
3. inspect the exact causal chain;
4. edit a small amount of DSL;
5. compile successfully;
6. rerun deterministically;
7. observe a different tactical result.

Do not proceed to campaign scope until this is consistently satisfying.

## Milestone 12 — Workbench polish

### Tasks

- [ ] Add syntax highlighting.
- [ ] Add inline diagnostics.
- [ ] Add type-directed completion.
- [ ] Add go-to definition.
- [ ] Add documentation panel.
- [ ] Add formatting.
- [ ] Add doctrine version history.
- [ ] Add diff view.
- [ ] Add selected-entity trace mode.
- [ ] Implement bitmap-font rendering and scaling.
- [ ] Add accessibility options.

### Exit criteria

- A new player can make the intended tutorial edit without external documentation.
- Font is readable at supported resolutions.
- The editor never exposes host filesystem access through user code.

## Milestone 13 — Persistent squad layer

Post-vertical-slice.

### Tasks

- [ ] Roster management.
- [ ] Equipment inventory.
- [ ] Injury and recovery.
- [ ] Mission history.
- [ ] Capability unlocks.
- [ ] Doctrine assignment per operative or role.
- [ ] Save migration.
- [ ] Campaign progression skeleton.

## Milestone 14 — Content and sharing

Post-alpha.

### Tasks

- [ ] Additional mission archetypes.
- [ ] Data-driven content tooling.
- [ ] Doctrine package export/import.
- [ ] Challenge package format.
- [ ] Headless benchmark runner.
- [ ] Content licence manifest.
- [ ] Workshop or sharing integration only after formats stabilise.

## Continuous requirements

Apply to every milestone:

- [ ] Add tests.
- [ ] Preserve deterministic ordering.
- [ ] Update documentation for interface changes.
- [ ] Add canonical events for new simulation outcomes.
- [ ] Add causal provenance for player-visible decisions.
- [ ] Validate serialization and replay compatibility.
- [ ] Avoid gameplay logic in rendering code.
- [ ] Avoid hidden mutation in the DSL runtime.
- [ ] Keep the vertical slice runnable.
