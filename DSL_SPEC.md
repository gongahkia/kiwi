# Functional DSL Specification

## 1. Purpose

The Doctrine DSL is a small, pure, statically typed functional language used to define squad coordination, operative behaviour, and specialised equipment controllers.

The language must be:

- approachable from templates;
- deterministic;
- sandboxed;
- inspectable;
- resource-bounded;
- source-mappable;
- suitable for causal tracing;
- expressive enough to build tactical policies from a small core.

The language is not intended to be a general-purpose replacement for Lua.

## 2. Evaluation model

User programs do not mutate the world.

Each entry point consumes immutable input values and returns new state plus typed outputs.

```text
act : OperativeObservation -> OperativeMemory
    -> (OperativeMemory, List Intent)
```

Evaluation is pure with respect to the game world. Randomness, time, and hidden state are not implicit globals.

## 3. Language layers

### 3.1 Surface language

The player-facing language includes:

- readable declarations;
- pattern matching;
- records;
- lists;
- pipelines;
- standard-library functions;
- domain-specific literals such as `5m`, `250ms`, and `30deg`.

### 3.2 Desugared core

The surface language compiles into a deliberately small core containing:

- literals;
- variables;
- lambda functions;
- function application;
- lexical `let`;
- conditionals;
- algebraic data constructors;
- pattern matching;
- records and field access;
- list constructors;
- bounded primitive folds.

### 3.3 Bytecode

The core compiles to deterministic stack or register bytecode executed by a custom VM.

The bytecode must preserve:

- function boundaries;
- source spans;
- type IDs;
- instruction costs;
- trace points;
- stable serialization version.

## 4. Syntax overview

Illustrative syntax:

```text
module FieldPolicy

expose act

act view memory =
  let danger = dangerScore view
  in
  case nearestCasualty view of
    Some ally ->
      if danger < 0.60
      then (memory, moveAndStabilise view ally)
      else (memory, requestCover ally.position)

    None ->
      engageOrAdvance view memory
```

The exact punctuation may evolve, but the semantic model must remain stable.

## 5. Core constructs

### 5.1 Literals

- `Int`
- `Float`
- `Bool`
- `String`
- domain quantities
- tagged constructors
- lists
- records

### 5.2 Bindings

All names are immutable.

```text
let score = threatScore target
```

Shadowing may be permitted but should trigger an optional warning.

### 5.3 Functions

```text
exposurePenalty self cover =
  lineOfFireRisk self.position cover.position
```

Functions are first-class values where safe and useful.

### 5.4 Application

```text
threatScore target
```

Application associates left.

### 5.5 Pipelines

```text
visibleThreats view
  |> filter isHostile
  |> sortByDescending threatScore
  |> first
```

Pipelines are surface sugar for function application.

### 5.6 Conditional

```text
if healthRatio self < 0.25
then seekExtraction view
else continueMission view
```

Both branches must have compatible types.

### 5.7 Pattern matching

```text
case assignedTarget view of
  Some target -> engage target
  None -> seekUsefulPosition view
```

Pattern matching must be exhaustive unless an explicit wildcard is used.

### 5.8 Records

```text
{ destination = point
, stance = Crouched
, urgency = High
}
```

Initial implementation should prefer nominal domain records at API boundaries and structural records internally only where implementation complexity remains manageable.

### 5.9 Lists

Lists are immutable and bounded by runtime limits.

User code may call bounded standard-library combinators:

- `map`
- `filter`
- `fold`
- `any`
- `all`
- `first`
- `firstApplicable`
- `minimumBy`
- `maximumBy`

The VM must charge instruction cost proportional to traversed elements.

## 6. Types

### 6.1 Primitive types

- `Int`
- `Float`
- `Bool`
- `String`
- `Unit`

### 6.2 Domain quantity types

Use distinct types rather than untyped numbers:

- `Duration`
- `Distance`
- `Speed`
- `Angle`
- `Probability`
- `HealthRatio`
- `ThreatScore`
- `EntityId`
- `Position`
- `Direction`
- `Region`

Where feasible, dimensional arithmetic should be checked:

```text
Distance / Duration -> Speed
Speed * Duration -> Distance
```

The MVP may implement a limited predefined set rather than a complete dimensional type system.

### 6.3 Algebraic data types

Built-ins:

```text
Option a = None | Some a
Result error value = Err error | Ok value
```

Domain examples:

```text
Stance = Standing | Crouched | Prone
Urgency = Low | Normal | High | Critical
ContactClass = Unknown | Civilian | Hostile | Friendly
```

### 6.4 Function types

```text
threatScore : Track -> ThreatScore
```

### 6.5 Records

Example:

```text
Track {
  id : Option EntityId,
  position : Position,
  velocity : Vector,
  confidence : Probability,
  errorRadius : Distance,
  observedAt : SimTime,
  classification : ContactClass
}
```

## 7. Entry points

### 7.1 Operative policy

```text
act : OperativeObservation -> OperativeMemory
    -> (OperativeMemory, List Intent)
```

### 7.2 Squad coordinator

```text
coordinate : SquadObservation -> DoctrineState
           -> (DoctrineState, List Assignment)
```

### 7.3 Equipment controller

Examples:

```text
grenadeSolution : BlastContext -> Option ThrowPlan
breachPlan : BreachContext -> Result BreachError BreachPlan
```

## 8. Explicit memory

Programs cannot use hidden mutable state.

Memory is a serializable value passed into and returned from each evaluation.

Example:

```text
Memory {
  lastKnownThreat : Option Track,
  currentRole : Role,
  lastRepathAt : SimTime
}
```

The compiler validates that memory types are serializable and bounded.

Memory version changes require migration or reset rules when deploying a new doctrine version.

## 9. Intent model

The initial intent set should remain small.

```text
Intent
  = Move MoveRequest
  | TakeCover CoverRequest
  | Aim AimRequest
  | Fire FireRequest
  | Use UseRequest
  | Stabilise StabiliseRequest
  | Breach BreachRequest
  | Emit MessageEnvelope
  | Wait Duration
```

An intent is a request to the simulation. It does not encode success.

Each intent receives a stable ID so that later events can reference it.

## 10. Observations

Observations are immutable snapshots assembled from permitted sensors and messages.

Operative observation categories:

- self state;
- visible geometry;
- perceived contacts;
- nearby cover;
- current assignments;
- received signals;
- recent intention results;
- communication state;
- mission clock;
- known objective state.

The observation must not include hidden authoritative world data.

## 11. Standard library

### 11.1 Design rule

The standard library should make useful tactics easy without turning high-level tactics into uninspectable engine magic.

Every standard-library function must be:

- deterministic;
- traceable;
- documented with a type;
- implemented in the same semantic model or exposed as a pure host intrinsic;
- associated with an instruction cost;
- testable in isolation.

### 11.2 Initial modules

#### `List`

- `map`
- `filter`
- `fold`
- `first`
- `firstApplicable`
- `minimumBy`
- `maximumBy`
- `sortBy`
- `take`

#### `Option`

- `map`
- `withDefault`
- `andThen`
- `isSome`

#### `Math`

- bounded arithmetic;
- clamp;
- interpolation;
- safe division;
- probability helpers.

#### `Geometry`

- distance;
- direction;
- angle difference;
- region containment;
- line intersection helpers based only on observed geometry.

#### `Threat`

- baseline threat scoring;
- exposure estimate;
- target ownership helpers;
- stale-track penalties.

#### `Movement`

- move toward region;
- maintain distance;
- maintain support position;
- avoid occupied cover;
- formation anchors.

#### `Cover`

- score cover;
- select cover against a threat set;
- estimate exposure;
- reserve cover through messages.

#### `Squad`

- assign roles;
- allocate targets;
- select casualty response;
- maintain spacing;
- determine extraction readiness.

#### `Intent`

Constructors and safe helpers for valid requests.

## 12. Beginner-facing templates

The first doctrine should not be blank.

Example:

```text
chooseAction view =
  [ evacuateIfCritical
  , stabiliseNearbyAlly
  , escapeImmediateThreat
  , engageAssignedTarget
  , takeUsefulCover
  , pursueObjective
  ]
  |> firstApplicable view
```

The editor should allow the player to:

- reorder behaviours;
- adjust thresholds;
- replace one function;
- inspect types;
- run local examples.

## 13. Restrictions

The MVP prohibits:

- user-defined recursion;
- infinite or unbounded loops;
- mutable global variables;
- IO;
- host language calls;
- dynamic code loading;
- reflection;
- threads;
- exceptions;
- null;
- nondeterministic iteration;
- unbounded allocation;
- unrestricted strings as message payloads.

Later recursion may be permitted only with structural termination checks or explicit fuel.

## 14. Compiler pipeline

```text
Source text
  -> lexer
  -> parser
  -> concrete syntax tree
  -> name resolution
  -> typed AST
  -> exhaustiveness checks
  -> capability checks
  -> desugared core AST
  -> optimisation
  -> bytecode
  -> verification
  -> deployable program package
```

### 14.1 Parser

Requirements:

- precise source spans;
- recoverable diagnostics;
- stable grammar tests;
- comments;
- useful expected-token messages.

### 14.2 Type inference

Prefer local or Hindley–Milner-style inference for ordinary functions, while requiring explicit annotations at module boundaries and public entry points.

Avoid advanced type-system features in the first implementation.

### 14.3 Capability checking

A doctrine package declares required capabilities.

Example:

```text
requires [Rifle, Radio, MedicalKit]
```

Deployment validates that assigned operatives expose those capabilities.

### 14.4 Cost analysis

Every bytecode instruction has a deterministic cost.

The compiler estimates common-case and maximum bounded cost where possible.

Programs exceeding hard limits do not deploy. Programs near limits produce warnings.

## 15. Intermediate representation

The core IR should be typed or type-annotated enough to validate bytecode generation.

Suggested nodes:

```text
Const
Local
Closure
Call
Let
If
Construct
Match
Record
GetField
ListNil
ListCons
Intrinsic
Return
Trace
```

Optimisations should remain conservative:

- constant folding;
- dead branch elimination;
- simple inlining;
- constructor simplification;
- pipeline desugaring;
- tail-position marking.

Never optimise away trace semantics without preserving source provenance.

## 16. VM

### 16.1 Requirements

- deterministic execution;
- no access to host globals;
- bounded stack;
- bounded heap;
- bounded list lengths;
- instruction fuel;
- stable value serialization;
- source mapping;
- trace hooks;
- explicit intrinsic table;
- clean error values rather than host crashes.

### 16.2 Runtime failure values

Examples:

- `OutOfFuel`
- `MemoryLimitExceeded`
- `InvalidIntrinsicArgument`
- `ProgramVersionMismatch`
- `MemoryMigrationFailed`
- `CapabilityUnavailable`

The engine applies a configured fallback policy when evaluation fails.

### 16.3 Fallback policy

Default safe fallback:

- stop advancing;
- seek nearby cover if possible;
- avoid firing;
- broadcast distress;
- preserve current objective metadata;
- await a later successful tick or extraction signal.

Fallback behaviour must be visible in traces.

## 17. Source maps and causal instrumentation

Every meaningful bytecode range maps to:

- module;
- function;
- source span;
- expression ID;
- optional semantic label.

Evaluation can emit structured trace records:

```text
EvaluationTrace {
  evaluationId,
  entityId,
  programVersion,
  tick,
  expressionId,
  inputs,
  output,
  instructionCost,
  parentEvaluationId
}
```

Trace recording modes:

- off;
- summary;
- selected entities;
- full mission;
- sampled.

## 18. Diagnostics

Diagnostics should be domain-aware.

Example:

```text
WARNING D208

The `Advance` branch does not handle `AllyDown`.
The operative will use the squad fallback policy when that event occurs.

  28 | case event of
  29 |   Contact threat -> engage threat
     |   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

Diagnostics categories:

- syntax;
- type;
- exhaustiveness;
- capability;
- cost;
- deployment;
- memory migration;
- unreachable branch;
- suspicious tactical assumption.

Tactical warnings must remain conservative and clearly identified as warnings, not compiler truth.

## 19. Versioning

A program package contains:

```text
ProgramPackage {
  languageVersion,
  bytecodeVersion,
  standardLibraryVersion,
  sourceHash,
  bytecodeHash,
  modules,
  entryPoints,
  capabilityManifest,
  memorySchema,
  sourceMap
}
```

Replay files must record exact package hashes.
