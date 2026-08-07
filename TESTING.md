# Testing Strategy

## 1. Principles

1. Core behaviour is tested headlessly.
2. Determinism is an explicit test target, not an assumption.
3. Compiler stages have independent fixtures.
4. Diagnostics are durable outputs and require tests.
5. Causal explanations are tested as graph queries, not screenshots.
6. Generated and property tests complement hand-authored examples.
7. Performance budgets are measured before native optimisation.
8. Graphical smoke tests never substitute for authoritative tests.

## 2. Test categories

### 2.0 Performance measurement

Use `make benchmark` or `uv run --extra dev python -m kiwi.cli benchmark source.dtr fixture.kfixture.json --entry choose --arg true --iterations 100 --ticks 60` for focused local measurements. The report covers full compilation, VM entry evaluation, headless ticks, retained trace capture, and replay packet encode/decode. It reports operation-normalized elapsed time only; host-dependent timings are not CI thresholds.

### 2.0.1 Manual Terminal usability drill

Use `make terminal` for an observer-led local session. After the briefing opens the default live preview, ask the participant to explain the `1m` uncertainty threshold, identify the source selected by the injury debrief, change only `1m` to `0m`, and explain the resulting replay comparison. Record task completion, observed confusion, and verbatim feedback outside the repository with participant consent; do not commit personal data or claim results that were not collected.

### 2.1 Unit tests

Cover pure functions and local invariants:

- tokenisation;
- parser precedence;
- source spans;
- name resolution;
- type operations;
- quantity arithmetic;
- core lowering;
- bytecode encoding;
- VM instructions;
- geometry intersections;
- cover exposure;
- deterministic random streams;
- event construction;
- trace query helpers;
- retained selection, rejection, failure, and consequence-chain query evidence;
- trace-query CLI output and malformed-packet handling;
- trace capture preserves canonical state hashes;
- format validation.

### 2.2 Golden tests

Golden fixtures are appropriate for:

- token streams;
- formatted AST or typed IR;
- diagnostic rendering;
- bytecode disassembly;
- canonical encoding;
- state hashes;
- explanation summaries;
- migration outputs.

Goldens must be human-reviewable and updated deliberately.

### 2.3 Property tests

Use Hypothesis after core representations stabilise.

Candidate properties:

- lexer never loses source coverage;
- parser pretty-print round trip for supported syntax;
- canonical encoding round trip;
- canonical map order independent of insertion order;
- quantity arithmetic obeys bounds and unit rules;
- bytecode encode/decode round trip;
- VM evaluation is deterministic;
- state hashing is stable under non-authoritative field changes;
- replay command serialisation round trip;
- line-segment intersection symmetry where applicable;
- path tie-breaking remains stable;
- trace recording does not alter authority.

Record seeds or examples on failure.

### 2.4 Fuzz tests

Fuzz boundaries:

- lexer and parser bytes;
- bytecode decoder;
- replay decoder;
- mission content loader;
- trace package loader.

Fuzzing must enforce size limits and ensure failures are structured rather than crashes or unbounded resource consumption.

### 2.5 Compiler integration tests

For each sample policy:

```text
source
 -> diagnostics or typed module
 -> bytecode
 -> VM result
 -> expected memory and intentions
```

Include valid and invalid cases.

### 2.6 VM safety tests

Test:

- instruction-budget exhaustion;
- allocation-budget exhaustion;
- stack-budget exhaustion;
- invalid bytecode rejection;
- malformed memory;
- malformed intention;
- closure capture;
- list traversal costs;
- deterministic fallback;
- no access to Python objects or IO.

### 2.7 Simulation tests

Small deterministic fixtures test:

- movement toward a point;
- obstacle collision;
- cover contention;
- visibility blocking;
- contact decay;
- message order;
- aim progression;
- aim reset after actual movement and retention after a blocked attempt;
- aim-rate equivalence at 20, 30, and 60 Hz;
- Aim and Fire capability, weapon-channel, ammunition, projectile, and aim-reset rules;
- projectile canonical state, provenance, ordering, and version rejection;
- projectile tunnelling prevention;
- earliest impact selection and obstacle, cover, operative tie precedence;
- projectile consumption, final-segment expiry, and map-boundary deferral;
- deterministic protection, injury bands, incapacitation, and condition versioning;
- deterministic damage, suppression radii, decay, stacking, and aim clamping;
- fire, projectile, impact, damage, injury, and suppression event order and causal parents;
- medical interruption;
- objective completion;
- command timing.

### 2.8 Replay tests

Test:

- repeated run hash equality;
- graphical adapter does not change hashes;
- replay recorder preserves canonical initial inputs, binding hashes, commands,
  and checkpoints;
- record then verify, including policy-version failures and earliest divergent
  checkpoint index, tick, expected hash, reconstructed hash, and sidecar-backed
  canonical-state field difference;
- checkpoint seek and resume from a replay-hash-bound periodic snapshot sidecar;
- replay-hash-bound historical-source sidecar preservation of exact UTF-8 text,
  source maps, bytecode, policy manifests, and corrupt-sidecar rejection;
- run comparison rejects every changed non-policy baseline input in stable order
  while reporting added, removed, and changed deployed policy versions;
- compatible headless-run comparison finds the first logical policy evaluation
  and intention delta while ignoring allocation-only IDs;
- retained causal-consequence comparison returns all logical added, removed,
  and changed outcomes while ignoring trace and authority allocation IDs;
- CLI replay record, verify, inspect, and compare operate headlessly on strict
  policy-free kernel-fixture replay packets and report structured mismatches;
- corrupt replay rejection;
- content hash mismatch;
- first-divergence reporting;
- unsupported version handling.

### 2.9 Causal-debugger tests

Fixtures should assert:

- source expression linked to intention;
- observation facts linked to branch;
- rejected intention has reason;
- projectile retains full Fire intention provenance through canonical round-trip;
- injury retains the projectile's full Fire intention provenance;
- “why not?” distinguishes absence from rejection;
- summary and full traces agree on high-level chain;
- comparison identifies first divergence;
- historical source is selected by bundle hash.

### 2.10 UI tests

Keep UI tests focused:

- text insertion, deletion, newline, indentation, and clipboard handoff;
- Unicode line indexing, cursor and directional selection;
- bounded logical scrolling and cursor visibility;
- lexer-derived source-token styling and bitmap-font rendering;
- inline source markers and canonical diagnostic panel rows;
- workbench compilation from immutable editor text and output-panel rendering;
- canonical development policy/fixture discovery, selection, and picker rendering;
- retained causal timeline ordering, selection, and bitmap rendering;
- retained event detail, causal-ancestor ordering, links, and bitmap rendering;
- archive-bound source selection, source-map highlights, and bitmap rendering;
- retained trace-to-source and historical-source-to-related-event navigation;
- compatibility-gated policy, state, consequence comparison, and bitmap rendering;
- versioned UI/font scale settings, safe fallback, and bitmap settings rendering;
- bounded undo and redo;
- diagnostic navigation;
- coordinate-to-source mapping;
- timeline filtering;
- snapshot combat projection and rendering smoke test with dummy SDL driver where supported;
- no authoritative mutation from UI actions.

## 3. Determinism harness

The determinism test runner should:

1. Load a fixture and compiled policy.
2. Run for a fixed number of ticks.
3. Record hashes at configured checkpoints.
4. Repeat in the same process.
5. Repeat in a fresh process where CI permits.
6. Compare final canonical state bytes on mismatch.
7. Optionally compare event streams to locate the first divergence.

Include tests with different insertion orders when constructing initial mappings.

The initial headless harness records authority snapshots at the initial tick,
each configured positive interval boundary, and the final tick. It repeats the
same immutable inputs in-process and returns a structured first-checkpoint
divergence with canonical field path and expected/actual values.

## 4. Canonical-state differential report

On hash mismatch, report the first differing canonical path:

```text
operatives/A2/position/x
expected: 12044
actual:   12045
first divergent tick: 218
```

This tooling is worth building early because deterministic defects are otherwise expensive to diagnose.

## 5. Static checks

The repository should run:

- Ruff formatting check;
- Ruff linting;
- static type checker;
- import-boundary test;
- forbidden API scan for authority packages, including `time`, unseeded `random`, `pickle`, and pygame imports;
- source encoding and asset licence checks where configured.

A targeted allowlist may be used for legitimate boundary modules.

## 6. Test fixtures

Fixture policy:

- small;
- deterministic;
- named by behaviour;
- versioned with content schema;
- no hidden dependency on global assets;
- expected outcomes documented;
- reusable by CLI and graphical development mode.

Recommended initial fixtures:

- `minimal` kernel fixture;
- `minimal_move`;
- `missing_contact`;
- `cover_contention`;
- `stale_threat_cover`;
- `projectile_impact`;
- `policy_budget_fault`;
- `causal_threshold_injury`;
- `terminal_vertical_slice`.

The current `cover_contention_policy` fixture emits the same requested-side
`TakeCover` intent for two operatives, asserting the canonical grant and
`slot_contested` loser. The `stale_threat_cover_policy` fixture receives a
decayed owner-local contact and asserts that `Cover.nearest_safe` still selects
the protected observed slot from that estimate. Both run through the headless
policy boundary and compare repeated events, checkpoints, and final hashes.

`projectile_impact_policy` retains explicit memory after one Fire request. Its
headless fixture asserts two advances, an operative impact, damage and injury
parents, retained Fire provenance, and deterministic near-miss then impact
suppression across three ticks.

`causal_threshold_injury` pairs a contact-precision threshold policy with a
one-shot hostile policy. It asserts the `Some` and threshold branches, observed
contact precision and visible cover, advance source span and route, then enemy
fire, projectile impact, injury, and the retained physical consequence chain.

The same fixture compiles the bundled Terminal scout policy, binds its normal
memory schema, and verifies its one-metre contact-uncertainty threshold through
the same advance, hostile fire, projectile impact, and injury chain.

The Terminal briefing/workbench tests preserve fixed briefing rows, canonical
roster order, independent editor state, compile-result invalidation, and
dummy-SDL bitmap rendering. They do not execute a policy or mutate authority.

Terminal language-guide tests retain one distinct lesson for every construct
used by the shipped scout policy, preserve bounded lesson navigation, and render
the selected lesson under dummy SDL without reading or changing policy text.

Terminal execution tests compile the current workbench sources, queue a player
start, advance one reducer tick at a time, and verify deterministic `advance`
and targeted `hold` signal provenance. Mission-summary tests project only the
authoritative objective lifecycle and lockdown state into in-progress, success,
and failure HUD output. The mission HUD test consumes the resulting presentation
snapshot, summary, and signal status under dummy SDL.

Terminal presentation-effect tests retain canonically ordered event-ID sound
cues, play each copied cue once under dummy SDL, and render current impact bursts
without writing authority state.

Terminal debrief tests assert canonical retained-injury selection, rejection
of missing trace evidence, causal-chain replacement, and dummy-SDL bitmap output.

Terminal guided-revision tests filter retained causes to editable player
policies, preserve matching compilation output while focusing provenance, reject
changed current source text, and render the focused workbench range under dummy
SDL.

Terminal controlled-rerun tests record resolved commands from the original
initial state, recompile one revised policy against that exact baseline, retain
replay-bound trace/source evidence, and reject a changed initial state before
comparison.

The `terminal_vertical_slice` acceptance fixture joins the player-facing loop:
briefing, scout compilation, headless mission setup, injury debrief, historical
source focus, a threshold revision, and replay-compatible comparison. Replacing
Lark's `1m` threshold with `0m` must remove the retained injury under the exact
same compact causal-fixture state, commands, tick rate, and tick count.

## 7. Compiler diagnostics tests

Test diagnostics as structured records:

- code;
- severity;
- primary span;
- secondary spans;
- message arguments;
- suggested action.

Rendered golden text is secondary. This avoids accidental coupling to whitespace while preserving UX examples.

## 8. Performance tests

Benchmark separately:

- lexer and parser per source size;
- type checking;
- bytecode compile;
- VM evaluations per second;
- policy budget overhead;
- simulation tick time by entity count;
- projectile and geometry query costs;
- summary and full trace overhead;
- trace size per simulated minute;
- replay verification speed;
- editor rendering at large files within supported limits.

Performance failures should report measured values and budgets. Avoid flaky wall-clock thresholds in ordinary CI; use generous regression limits or dedicated benchmark workflows.

## 9. Graphical-authority equivalence

Run the same fixture:

- through headless CLI;
- through an application session with pygame presentation disabled or dummy display;

Then compare authoritative hashes. Presentation frame rate and camera changes must not affect the result.

The Milestone 7 integration test runs a moving mission through the same fixed
reducer loop while dummy-SDL presentation repeatedly builds, renders, and
presents snapshots. It compares the resulting state hash and canonical event
identity with a headless run.

## 10. Mutation and negative testing

Where feasible, introduce controlled defects to ensure tests fail:

- change tie-break ordering;
- skip source-map link;
- alter command tick;
- omit a canonical field from hash;
- change a danger threshold;
- use unordered iteration.

The causal vertical-slice fixture should be sensitive to its defining policy change.

## 11. CI stages

Suggested pipeline:

1. formatting and lint;
2. static types and boundaries;
3. fast unit tests;
4. compiler goldens;
5. deterministic simulation and replay;
6. causal-query integration;
7. property tests;
8. optional graphical smoke;
9. optional performance trend.

Support at least macOS and one Linux environment before release. Windows support should be tested before claiming distribution.

## 12. Definition of done for language features

A language feature requires:

- syntax and semantics documented;
- parser tests;
- type tests;
- lowering tests;
- bytecode and VM tests where applicable;
- diagnostics;
- source-map coverage;
- cost and budget behaviour;
- formatter or stable printer update;
- versioning decision;
- example policy.

## 13. Definition of done for simulation features

A simulation feature requires:

- canonical state representation;
- deterministic phase and tie-break rules;
- input validation;
- structured events;
- causal links;
- replay coverage;
- state-hash inclusion where authoritative;
- headless fixture;
- relevant performance measurement;
- presentation snapshot fields if visible.

## 14. Definition of done for debugger features

A debugger feature requires:

- structured model;
- query semantics;
- fixture with known answer;
- summary rendering;
- source navigation where relevant;
- trace-level behaviour;
- retention impact;
- versioned format update if durable.

Trace-format tests additionally require canonical encode/decode equality,
stable packet hashes, ordered record and edge validation, and rejection of
unsupported or noncanonical packets.

VM trace instrumentation tests require deterministic source-map expression and
observation-field entries, executed conditional and Option-pattern selections,
stable policy-invocation joins, retained ordered contact evidence with confidence
and age, stable standard-library List selection and ranking source indices,
Cover candidate decisions, canonical intention-origin links through policy
validation and arbitration, canonical world-event parent chains, projectile
provenance through injury consequences, and identical traced and untraced
authority successors. Retention tests require level-specific record filtering,
deterministic trailing-tick windows, bounded record and edge selection, and no
dangling retained edges.
