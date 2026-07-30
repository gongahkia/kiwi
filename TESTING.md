# Testing Strategy

## 1. Principles

- Simulation correctness must be testable headlessly.
- Determinism is a first-class feature, not an incidental property.
- User programs must never crash the host runtime.
- Compiler and VM behaviour require stronger tests than ordinary UI code.
- Every bug involving replay divergence should receive a permanent regression test.
- Tests should prefer stable semantic assertions over screenshots, except for selected rendering goldens.

## 2. Test categories

### 2.1 Unit tests

Cover:

- lexer tokens;
- parser nodes;
- source spans;
- name resolution;
- type inference;
- pattern exhaustiveness;
- capability checks;
- bytecode emission;
- bytecode verification;
- VM instructions;
- intrinsic functions;
- observation building;
- intent validation;
- damage calculations;
- objective transitions;
- event serialization;
- state hashing.

### 2.2 Golden tests

Use golden fixtures for:

- parser AST output;
- formatted source;
- compiler diagnostics;
- typed AST snapshots;
- bytecode disassembly;
- source maps;
- explanation output;
- replay metadata;
- content validation reports.

Golden updates must be reviewed, not automatically accepted.

### 2.3 Property tests

Suggested properties:

- parse(format(ast)) preserves semantics;
- serialise(deserialise(value)) round-trips;
- type-correct source never emits invalid bytecode;
- verified bytecode never accesses outside VM bounds;
- exhaustive pattern checking agrees with constructor coverage;
- deterministic list functions preserve stable order;
- intent IDs are unique within a run;
- state hash is independent of table insertion order;
- observation never exposes hidden fields;
- replay of the same input stream reproduces hashes;
- branch replay diverges only after changed inputs or program packages.

### 2.4 Fuzz tests

Fuzz:

- lexer and parser input;
- bytecode verifier;
- replay loader;
- content loader;
- message payload decoder;
- save migration logic.

Requirements:

- no host crash;
- bounded execution;
- structured errors;
- no unbounded allocation.

### 2.5 Simulation tests

Small deterministic scenarios:

- one operative moves to a point;
- two operatives contend for cover;
- message arrives after configured latency;
- stale track decays;
- projectile strikes cover;
- projectile misses due to deterministic spread;
- cover destruction invalidates a plan;
- medic stabilises an ally;
- suppression changes observation and action selection;
- extraction objective completes;
- fallback policy runs after VM fuel exhaustion.

### 2.6 Replay tests

For each replay fixture:

- load metadata;
- validate hashes;
- rerun headlessly;
- compare canonical state hashes;
- compare event sequence;
- seek from snapshots;
- regenerate selected traces;
- reject incompatible versions cleanly.

### 2.7 Causal-debugger tests

Given a known scenario, assert that explanation queries identify:

- selected behaviour;
- rejected alternatives;
- source expression;
- observation values;
- intention outcome;
- physical failure reason;
- first divergent decision between two runs.

### 2.8 Performance tests

Track:

- ticks per second in headless mode;
- VM evaluations per second;
- trace overhead;
- observation-building cost;
- spatial-query cost;
- serialization cost;
- replay seek time;
- memory usage over long runs.

Performance tests should report trends rather than use fragile hard failures initially.

## 3. Determinism test harness

The harness runs the same mission multiple times and records:

- tick hash;
- event count;
- event hash;
- random stream states;
- objective state;
- final result.

On divergence, produce:

- first divergent tick;
- component-level hash differences;
- differing event IDs;
- differing random stream state;
- recent inputs and program evaluations.

## 4. VM safety tests

Test:

- stack overflow prevention;
- heap limit;
- instruction fuel;
- invalid opcode;
- invalid constant index;
- invalid jump target;
- malformed closure;
- wrong intrinsic arity;
- wrong intrinsic type;
- oversized list;
- recursive or cyclic values;
- memory migration failure;
- trace mode correctness.

The verifier should reject malformed bytecode before execution whenever possible.

## 5. Compiler diagnostics tests

Each diagnostic fixture includes:

- source;
- expected code;
- expected source span;
- expected message fragment;
- expected severity;
- optional suggested fix.

Diagnostics must not drift silently.

## 6. Content validation

Validate every mission, operative, equipment item, and doctrine package for:

- unique IDs;
- required fields;
- valid references;
- supported versions;
- valid geometry bounds;
- valid capabilities;
- valid objective graphs;
- deterministic ordering;
- licence metadata for external assets;
- absence of inaccessible source files in release packages.

## 7. CI expectations

CI should run:

1. formatting or lint checks;
2. unit tests;
3. compiler goldens;
4. property tests with fixed seeds;
5. deterministic simulation fixtures;
6. replay validation;
7. content validation;
8. headless vertical-slice smoke test.

Nightly or manual jobs may run:

- extended property tests;
- fuzzing;
- larger performance suites;
- cross-platform replay comparison.

## 8. Test fixture policy

- Keep fixtures small and human-readable.
- Store exact program package and content hashes.
- Never modify a replay fixture without documenting why.
- Add a fixture for every serious causal-debugger bug.
- Prefer minimal reproductions over full mission captures.

## 9. Definition of done for simulation features

A simulation feature is not done until it has:

- deterministic behaviour;
- canonical events;
- serialization;
- state hashing;
- headless tests;
- debugger provenance;
- player-visible diagnostics where relevant.
