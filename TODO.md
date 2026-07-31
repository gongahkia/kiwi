# Implementation TODO

This plan assumes a fresh repository. Work in milestone order. Do not begin a later milestone until the current milestone’s exit criteria pass, except for minimal stubs needed to compile or test the current work.

Each checked item must correspond to concrete verification evidence and a git commit or a clearly documented tightly coupled commit group.

## Milestone 0 — Repository and engineering skeleton

### Goal

Create a reproducible Python project with headless architecture boundaries and stable developer commands.

### Tasks

- [x] Initialise git repository and add the documentation packet.
- [x] Create `pyproject.toml` with Python 3.12+ metadata and src layout.
- [x] Select and document canonical environment workflow; support standard venv/pip even if `uv` is preferred.
- [x] Add runtime dependency on pygame-ce only.
- [x] Add development dependencies for pytest, Ruff, one static type checker, and coverage if desired.
- [x] Create `src/kiwi` package and initial `domain`, `dsl`, `sim`, `trace`, `replay`, `content`, `app`, `render`, and `ui` packages.
- [x] Add `kiwi.cli` with a `doctor` command that runs headlessly.
- [x] Add minimal test structure.
- [x] Configure formatting and linting.
- [x] Configure static type checking.
- [x] Add import-boundary tests proving authoritative packages do not import pygame or presentation packages.
- [x] Add forbidden-API scan or tests for `eval`, `exec`, `pickle`, wall-clock access, and unseeded randomness in authority packages.
- [x] Add canonical commands through Makefile, justfile, or documented Python commands.
- [x] Add CI for formatting, linting, static checking, and tests.
- [x] Update README with setup and commands.

### Exit criteria

- [x] Fresh checkout can install and run checks using documented commands.
- [x] `python -m kiwi.cli doctor` succeeds without importing pygame.
- [x] Empty or minimal test suite passes.
- [x] Import-boundary and forbidden-API checks pass.
- [x] Repository is formatted, linted, type checked, and clean.
- [x] Milestone committed.

## Milestone 1 — Source model, lexer, and parser

### Goal

Parse a tiny functional policy language into immutable syntax with accurate source spans and structured diagnostics.

### Required subset

- integer and boolean literals;
- identifiers;
- named function or policy declaration;
- parameters and return annotation;
- function application;
- `let`;
- `if`;
- parentheses;
- comments.

### Tasks

- [x] Define source file IDs, offsets, line index, positions, and spans.
- [x] Define token kinds and immutable token values.
- [x] Implement UTF-8 source loading with size limits.
- [x] Implement lexer with comments, keywords, identifiers, punctuation, integers, booleans, and diagnostics.
- [x] Define immutable surface AST with source spans on every node.
- [x] Select and implement parser architecture, preferably hand-written recursive descent plus Pratt parsing where useful.
- [x] Parse policy declarations, types, applications, `let`, and `if`.
- [x] Implement parser recovery sufficient to return multiple useful diagnostics.
- [x] Define structured diagnostic model with stable codes.
- [x] Add a stable debug printer for tokens and AST.
- [x] Add lexer and parser golden fixtures.
- [x] Add source-span edge-case tests for multiline and invalid input.
- [x] Add CLI `parse` command.

### Exit criteria

- [x] The first proof policy parses.
- [x] Invalid examples report exact spans and stable diagnostic codes.
- [x] Lexer and parser do not crash on bounded arbitrary input tests.
- [x] AST debug output is deterministic.
- [x] All checks pass and milestone is committed.

## Milestone 2 — Names, types, and typed core

### Goal

Resolve names and reject invalid programs before execution.

### Required subset

- `Int`, `Bool`, `Unit`;
- function types;
- explicit annotations on named functions;
- local inference;
- lexical scope;
- branch type agreement;
- typed core IR.

### Tasks

- [x] Define type algebra and stable type rendering.
- [x] Define symbol and definition IDs independent of Python object identity.
- [x] Implement lexical environments and name resolution.
- [x] Detect unknown names, duplicates, invalid arity, and prohibited shadowing.
- [x] Implement type checking for literals, names, application, `let`, and `if`.
- [x] Define typed AST or typed surface representation.
- [x] Define minimal core IR with stable expression IDs.
- [x] Lower typed syntax into core IR.
- [x] Preserve source-map links through lowering.
- [x] Add diagnostics for type mismatch, branch mismatch, unknown name, and invalid call.
- [x] Add golden typed-core fixtures.
- [x] Add CLI `check` command.

### Exit criteria

- [x] Valid proof policy produces typed core.
- [x] Invalid calls and mismatched branches fail with source diagnostics.
- [x] Core expression IDs and ordering are deterministic.
- [x] No Python type objects leak into durable compiler output.
- [x] All checks pass and milestone is committed.

## Milestone 3 — Bytecode, runtime values, and deterministic VM

### Goal

Compile and execute the tiny language without Python `eval` or `exec`.

### Tasks

- [x] Define bytecode version and module header.
- [x] Define closed runtime-value algebra.
- [x] Define canonical constant-pool and function ordering.
- [x] Define initial instruction set.
- [x] Compile core IR to bytecode.
- [x] Implement bytecode validator.
- [x] Implement bytecode disassembler.
- [x] Implement deterministic stack VM.
- [x] Implement call frames and local slots.
- [x] Enforce instruction, stack, call-depth, and allocation budgets.
- [x] Implement structured VM faults.
- [x] Implement deterministic fallback result for policy faults.
- [x] Add source mapping from instructions and expressions to spans.
- [x] Add bytecode encode/decode format without pickle.
- [x] Add VM unit, golden, and safety tests.
- [x] Add CLI `compile`, `disassemble`, and `run-policy` commands.

### Exit criteria

- [x] Same typed core produces byte-identical bytecode.
- [x] Proof policy executes to an expected value.
- [x] Budget exhaustion is deterministic and source linked.
- [x] Invalid bytecode is rejected before execution.
- [x] Repository scan confirms no Python code execution path for player source.
- [x] All checks pass and milestone is committed.

## Milestone 4 — Language MVP data types

### Goal

Add the functional data features required by tactical policies.

### Tasks

- [x] Add string and exact domain-quantity literals.
- [x] Implement records and field access.
- [x] Implement built-in algebraic variants, beginning with `Option`.
- [x] Implement exhaustive pattern matching.
- [x] Implement immutable lists.
- [x] Implement anonymous functions with bounded closures.
- [x] Implement pipeline syntax as desugaring.
- [x] Add bounded `List.map`, `filter`, `fold`, `find`, `min_by`, and `sort_by` intrinsics.
- [x] Define deterministic tie-breaking for collection selection and sorting.
- [x] Add memory and decision record validation.
- [x] Add domain type operations for duration, distance, probability, position, and vector.
- [x] Reject dimensionally invalid operations.
- [x] Add capability manifest skeleton.
- [x] Add full language diagnostics and golden fixtures.
- [x] Update language version and documentation examples if syntax changes.

### Exit criteria

- [x] A policy using records, `Option`, matching, a list operation, quantity comparison, memory, and an intention value compiles and executes.
- [x] Incomplete matches fail statically.
- [x] Domain quantity errors fail statically.
- [x] Collection costs count toward VM budgets.
- [x] All checks pass and milestone is committed.

## Milestone 5 — Headless simulation kernel

### Goal

Create deterministic fixed-step authority with commands, events, hashing, and snapshots but no tactical detail.

### Tasks

- [x] Define canonical quantity and geometry representations.
- [x] Define typed IDs and deterministic ID allocation.
- [x] Define mission state and entity skeleton.
- [x] Implement fixed tick clock.
- [x] Define external command schema and canonical ordering.
- [x] Define deterministic scheduled-event queue.
- [x] Define named deterministic random streams and draw records.
- [x] Define canonical event algebra.
- [x] Implement one-tick reducer pipeline.
- [x] Implement canonical state encoding and hashing.
- [x] Implement canonical snapshots distinct from presentation snapshots.
- [x] Add headless runner for N ticks.
- [x] Add determinism harness and differential report.
- [x] Add fixture content loader with validation.

### Exit criteria

- [x] Repeated minimal runs produce identical checkpoint hashes.
- [x] Initial mapping insertion order does not affect hashes.
- [x] Snapshot restore continues with identical hashes.
- [x] No pygame import occurs.
- [x] All checks pass and milestone is committed.

## Milestone 6 — Policies, observations, memory, and intentions

### Goal

Connect compiled policies to the simulation without adding combat.

### Tasks

- [x] Define runtime observation value schema.
- [x] Define policy memory storage per entity.
- [x] Define core intention variants and action channels.
- [x] Define intention IDs and source origin metadata.
- [x] Build immutable observations from pre-evaluation state.
- [x] Invoke policy VM in canonical entity order.
- [x] Validate returned memory and intentions.
- [x] Implement capability checks for available intention families.
- [x] Implement ordered per-channel arbitration.
- [x] Emit policy, intention, rejection, and selection events.
- [x] Implement deterministic fallback on VM fault.
- [x] Include memory and policy version in canonical state.
- [x] Add first end-to-end fixture where policy emits `Wait` or movement intention.

### Exit criteria

- [x] DSL source compiles and changes simulation events.
- [x] Identical run produces identical intentions and hashes.
- [x] Invalid memory or intention produces structured fallback.
- [x] Intention events retain source expression ID.
- [x] All checks pass and milestone is committed.

## Milestone 7 — Movement, geometry, and graphical shell

### Goal

Resolve movement headlessly and display the same state through pygame-ce.

### Tasks

- [x] Select and document operative footprint representation.
- [x] Implement obstacle and map geometry.
- [x] Implement deterministic path representation and path query.
- [x] Implement stable A* or selected path algorithm with canonical ties.
- [x] Implement movement action state and per-tick progression.
- [x] Implement obstacle collision and bounded operative separation.
- [x] Emit movement, block, and arrival events.
- [x] Add presentation snapshot model.
- [x] Initialise pygame-ce only in render/application packages.
- [x] Implement window, logical canvas, camera, and basic map rendering.
- [x] Render operatives, obstacles, paths, and objective marker.
- [x] Add headless-versus-graphical authority equivalence test.
- [x] Add basic bitmap font loading and nearest-neighbour scaling.

### Exit criteria

- [x] A compiled policy moves an operative around an obstacle to an objective.
- [x] Path ties and occupancy conflicts are deterministic.
- [x] Graphical rendering does not alter state hashes.
- [x] Application starts and exits cleanly on supported development platform.
- [x] All checks pass and milestone is committed.

## Milestone 8 — Perception, contacts, and communication

### Goal

Replace omniscient policy input with incomplete information.

### Tasks

- [x] Implement deterministic visibility queries.
- [x] Add sensor ranges and visible geometry.
- [x] Define contact estimates, confidence, age, and uncertainty.
- [x] Implement contact creation, update, decay, and loss.
- [x] Add observation provenance for contact fields.
- [x] Define typed messages and inbox observations.
- [x] Implement deterministic send and delivery ordering.
- [x] Add squad signals as tick-stamped commands and observation values.
- [ ] Add communication events and causal links.
- [ ] Render contact uncertainty and visibility overlays.
- [ ] Add fixtures for missing, stale, and relayed information.

### Exit criteria

- [ ] Policies cannot access hidden enemy state.
- [ ] Contact behaviour is deterministic and replayed.
- [ ] A policy safely handles `Some(contact)` and `None`.
- [ ] Observation fields link to evidence events.
- [ ] All checks pass and milestone is committed.

## Milestone 9 — Cover, exposure, and tactical selection

### Goal

Make spatial safety a programmable tactical concern.

### Tasks

- [ ] Define cover segments, sides, occupancy slots, height, and integrity.
- [ ] Implement cover visibility and observed cover values.
- [ ] Implement deterministic exposure estimate against contacts.
- [ ] Implement cover reservation or contention rules.
- [ ] Add `TakeCover` intention validation and execution.
- [ ] Add standard-library cover selection helpers.
- [ ] Trace candidate cover scores, rejections, and selection.
- [ ] Render cover quality, threat direction, and occupancy.
- [ ] Add fixtures for cover contention and stale threat estimates.

### Exit criteria

- [ ] Policy can choose and occupy cover using only observed data.
- [ ] Equal cover candidates resolve canonically.
- [ ] Debug trace explains selected and rejected cover.
- [ ] All checks pass and milestone is committed.

## Milestone 10 — Aiming, firing, projectiles, damage, and suppression

### Goal

Create physically legible combat with deterministic consequences.

### Tasks

- [ ] Define weapons, ammunition, aim state, and fire capability.
- [ ] Implement aim progression and movement/suppression modifiers.
- [ ] Implement named random stream for dispersion if retained.
- [ ] Define projectile canonical state.
- [ ] Implement swept projectile movement and earliest collision.
- [ ] Implement impact with obstacles, cover, and operatives.
- [ ] Implement damage, injury, incapacitation, and basic protection.
- [ ] Implement suppression from shots and impacts.
- [ ] Add `Aim` and `Fire` intentions.
- [ ] Emit fire, projectile, impact, damage, injury, and suppression events.
- [ ] Add provenance from source intention to projectile and injury.
- [ ] Render projectiles, impacts, aim state, and suppression.
- [ ] Add deterministic projectile fixtures.

### Exit criteria

- [ ] A policy can observe, aim, and fire at a contact.
- [ ] Projectiles travel visibly and collide deterministically.
- [ ] Injury is linked to projectile and source intentions.
- [ ] Repeated runs match hashes and event chains.
- [ ] All checks pass and milestone is committed.

## Milestone 11 — Causal trace foundation

### Goal

Record and query structured code-to-consequence provenance.

### Tasks

- [ ] Define trace format version and model.
- [ ] Instrument policy invocation and expression IDs.
- [ ] Record observation-field reads at decision trace level.
- [ ] Record branch and pattern selections.
- [ ] Record standard-library semantic decisions.
- [ ] Connect intention origins to validation and arbitration.
- [ ] Connect world events to consequences.
- [ ] Implement trace levels and retention limits.
- [ ] Implement `why selected`, `why not selected`, and `why failed` queries.
- [ ] Implement consequence-chain query.
- [ ] Ensure trace capture does not affect state hashes.
- [ ] Add required `causal_threshold_injury` fixture.
- [ ] Add CLI trace query output.

### Exit criteria

- [ ] Injury fixture traces from source threshold to advance intention and injury.
- [ ] Query distinguishes program omission from simulation rejection.
- [ ] Summary and full trace agree on main chain.
- [ ] Trace-disabled and trace-enabled runs have identical authority.
- [ ] All checks pass and milestone is committed.

## Milestone 12 — Replay, seeking, and run comparison

### Goal

Support controlled experimentation between kiwi versions.

### Tasks

- [ ] Define replay format and version.
- [ ] Record initial inputs, content hashes, policy hashes, seeds, commands, and checkpoints.
- [ ] Implement replay verification.
- [ ] Implement periodic snapshot seeking.
- [ ] Implement first-divergent-checkpoint reporting.
- [ ] Implement canonical state differential report.
- [ ] Preserve historical source and source maps with run references.
- [ ] Implement run compatibility checks.
- [ ] Implement first divergent policy evaluation and intention comparison.
- [ ] Implement changed consequence comparison.
- [ ] Add CLI replay record, verify, inspect, and compare commands.

### Exit criteria

- [ ] Recorded run verifies from fresh process.
- [ ] Corrupt or incompatible runs fail clearly.
- [ ] Comparison identifies policy change, first divergence, and changed injury outcome in fixture.
- [ ] Historical source navigation is independent of current file contents.
- [ ] All checks pass and milestone is committed.

## Milestone 13 — Workbench and debugger UI

### Goal

Expose source editing, compilation, mission inspection, and causal navigation in pygame-ce.

### Tasks

- [ ] Implement text buffer, cursor, selection, scrolling, and line index.
- [ ] Implement insertion, deletion, newline, indentation, clipboard, undo, and redo.
- [ ] Render source with bitmap font and syntax token styling.
- [ ] Render inline and panel diagnostics.
- [ ] Add compile command and output panel.
- [ ] Add policy and fixture picker for development.
- [ ] Implement mission timeline.
- [ ] Implement event detail and causal-chain panel.
- [ ] Implement historical source pane and source highlighting.
- [ ] Implement trace-to-source and source-to-related-event navigation.
- [ ] Implement run comparison view.
- [ ] Add UI scale and readable font settings.
- [ ] Add asset licence manifest for bundled fonts.

### Exit criteria

- [ ] User can edit and compile without external editor.
- [ ] Compiler errors navigate to exact span.
- [ ] Injury event opens its causal chain and historical source.
- [ ] UI remains inspection-only for individual operatives.
- [ ] All headless checks remain independent of pygame.
- [ ] All checks pass and milestone is committed.

## Milestone 14 — Glasshouse vertical slice

### Goal

Deliver the complete product loop in one small mission.

### Tasks

- [ ] Finalise map and mission data.
- [ ] Add four player operative loadouts and policies.
- [ ] Add deterministic hostile behaviour using compatible policy concepts.
- [ ] Add objective retrieval and extraction.
- [ ] Add reinforcement or lockdown timer.
- [ ] Add flawed starting kiwi with intended explainable failure.
- [ ] Add briefing and kiwi workbench flow.
- [ ] Add mission execution and high-level signal support.
- [ ] Add debrief with selected injury consequence.
- [ ] Add guided source revision.
- [ ] Add controlled rerun and comparison.
- [ ] Add mission success and failure summaries.
- [ ] Add sound and restrained visual effects without authority changes.
- [ ] Add tutorial text for language constructs used.
- [ ] Add full automated vertical-slice fixture and acceptance test.
- [ ] Measure compiler, VM, tick, trace, and package performance.

### Exit criteria

- [ ] Fresh user can complete the full brief-to-debug-to-rerun loop.
- [ ] Initial and revised runs are deterministic.
- [ ] Debugger accurately explains the defining failure.
- [ ] Changed source produces a visible changed consequence.
- [ ] No later campaign systems are required.
- [ ] Full checks, replay verification, and packaged development build succeed.
- [ ] Milestone committed and tagged as vertical-slice baseline.

## Milestone 15 — Post-slice hardening

### Goal

Prepare the architecture for broader testing without prematurely building a full game.

### Tasks

- [ ] Run usability tests focused on language comprehension and causal explanation.
- [ ] Fix highest-impact diagnostic and debugger failures.
- [ ] Benchmark on target macOS and Linux systems; add Windows before claiming support.
- [ ] Select packaging approach through measured prototype.
- [ ] Add crash and corrupt-run recovery.
- [ ] Add content and policy project validation tooling.
- [ ] Write public technical overview and contributor setup.
- [ ] Decide next product slice using evidence.

### Exit criteria

- [ ] Known high-severity correctness and data-loss issues are resolved.
- [ ] Distribution assumptions are documented.
- [ ] Next milestone is based on tested product needs, not speculative scope.

## Deferred milestones

Do not schedule these until post-slice evidence supports them:

- persistent campaign and recovery;
- additional mission archetypes;
- richer user-defined types;
- in-mission hot deployment;
- policy package sharing;
- replay challenge sharing;
- advanced communication constraints;
- broader destructible environments;
- non-authoritative Pymunk effects;
- native acceleration of measured hot loops;
- modding;
- multiplayer.

## Continuous requirements

Apply throughout all milestones:

- [ ] Preserve deterministic ordering and canonical state.
- [ ] Preserve source spans and provenance.
- [ ] Keep authority independent of pygame.
- [ ] Avoid Python execution for DSL source.
- [ ] Add structured errors and diagnostics.
- [ ] Add or update tests.
- [ ] Update specifications when semantics or formats change.
- [ ] Review dependency licences and packaging effects.
- [ ] Keep commits independently valid and reversible.
- [ ] Do not mark TODO items complete without evidence.
