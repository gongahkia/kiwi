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
- projectile canonical state, provenance, ordering, and version rejection;
- projectile tunnelling prevention;
- earliest impact selection and obstacle, cover, operative tie precedence;
- damage and suppression;
- medical interruption;
- objective completion;
- command timing.

### 2.8 Replay tests

Test:

- repeated run hash equality;
- graphical adapter does not change hashes;
- record then verify;
- checkpoint seek and resume;
- corrupt replay rejection;
- content hash mismatch;
- first-divergence reporting;
- unsupported version handling.

### 2.9 Causal-debugger tests

Fixtures should assert:

- source expression linked to intention;
- observation facts linked to branch;
- rejected intention has reason;
- projectile linked to fire intention;
- injury linked to projectile impact;
- “why not?” distinguishes absence from rejection;
- summary and full traces agree on high-level chain;
- comparison identifies first divergence;
- historical source is selected by bundle hash.

### 2.10 UI tests

Keep UI tests focused:

- text buffer operations;
- cursor and selection;
- undo and redo;
- diagnostic navigation;
- coordinate-to-source mapping;
- timeline filtering;
- snapshot rendering smoke test with dummy SDL driver where supported;
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
- `glasshouse_vertical_slice`.

The current `cover_contention_policy` fixture emits the same requested-side
`TakeCover` intent for two operatives, asserting the canonical grant and
`slot_contested` loser. The `stale_threat_cover_policy` fixture receives a
decayed owner-local contact and asserts that `Cover.nearest_safe` still selects
the protected observed slot from that estimate. Both run through the headless
policy boundary and compare repeated events, checkpoints, and final hashes.

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
