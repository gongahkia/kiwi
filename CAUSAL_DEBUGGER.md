# Causal Debugger Specification

## 1. Purpose

The causal debugger is the defining product feature.

It must connect four layers:

1. What an operative could observe.
2. How the deployed program evaluated those observations.
3. Which intentions the program emitted.
4. How the physical simulation resolved those intentions.

The debugger should let a player understand not only what happened, but why the squad’s code contributed to it.

## 2. Required questions

The debugger should answer:

- Why did this operative move here?
- Why did this operative fire at this target?
- Why did this operative ignore another target?
- Why did the medic leave cover?
- Why was this cover selected?
- Why did this intent fail?
- Why did two operatives choose the same target?
- Which information was available at the decision time?
- Which information was stale or missing?
- Which source expression generated this value?
- Which doctrine version was running?
- What changed between two runs?

## 3. Causal chain model

Representative chain:

```text
Sensor observation
  -> Track update
  -> Observation snapshot
  -> Function evaluation
  -> Candidate scores
  -> Selected branch
  -> Emitted intention
  -> Intent validation
  -> Physical action
  -> Collision or interruption
  -> Damage event
  -> Mission consequence
```

Each node has stable IDs and links to predecessors.

## 4. Data model

### 4.1 Evaluation record

```text
EvaluationRecord {
  evaluationId,
  tick,
  entityId,
  programVersion,
  entryPoint,
  observationId,
  previousMemoryHash,
  newMemoryHash,
  result,
  instructionCost,
  rootTraceId
}
```

### 4.2 Expression trace

```text
ExpressionTrace {
  traceId,
  evaluationId,
  expressionId,
  sourceSpan,
  functionName,
  inputSummaries,
  outputSummary,
  parentTraceId,
  childTraceIds,
  instructionCost
}
```

### 4.3 Provenance edge

```text
ProvenanceEdge {
  fromId,
  toId,
  relation
}
```

Relations include:

- observed-as;
- derived-from;
- selected-by;
- rejected-by;
- emitted;
- validated-by;
- failed-because;
- caused;
- informed;
- delivered-from.

### 4.4 Intention outcome

```text
IntentOutcome {
  intentId,
  status,
  startedTick,
  endedTick,
  reason,
  relatedEvents,
  physicalEvidence
}
```

## 5. Trace levels

### Summary

Records:

- entry-point inputs and output;
- selected candidate;
- emitted intentions;
- runtime cost;
- errors.

### Decision

Adds:

- candidate list;
- applicability;
- scores;
- rejection reasons;
- relevant source spans.

### Full

Adds expression-level values and nested calls.

Full traces may be restricted to selected operatives or short windows due to volume.

## 6. Explanation queries

### 6.1 Why action selected?

Return:

- selected behaviour;
- relevant source span;
- branch condition values;
- competing behaviours;
- reasons competitors did not apply or scored lower;
- observation fields used;
- doctrine version.

### 6.2 Why action not selected?

For a candidate action:

- not applicable;
- lower score;
- lacked capability;
- pre-empted by earlier priority;
- invalid due to current state;
- absent from doctrine.

### 6.3 Why intent failed?

Separate program correctness from world resolution.

Example:

```text
Program decision: valid
Intent: TakeCover C12
Resolution: failed
Reason: C12 became occupied 0.15 s before arrival
Contributing cause: Ally H03 selected the same cover because no reservation message was emitted
```

### 6.4 Why was information wrong?

Explain:

- last observation time;
- source sensor;
- confidence;
- communication delay;
- track extrapolation;
- occlusion;
- contradictory update.

## 7. Source integration

Clicking an event should:

1. Select the responsible entity and time.
2. Open the source module and version used.
3. Highlight the expression that contributed to the decision.
4. Display values from that evaluation.
5. Show related upstream observations and downstream outcomes.

The debugger must display historical source, not merely the latest edited version.

## 8. Timeline UI

The timeline should support:

- mission scrubber;
- event lanes per operative;
- message lane;
- objective lane;
- projectile and damage markers;
- program deployment markers;
- filtering;
- bookmarks;
- jump to next injury, shot, failure, or message drop.

## 9. Counterfactuals

Counterfactual debugging is valuable but must be constrained.

Initial form:

- branch from a recorded snapshot;
- deploy a different doctrine;
- replay from that point with the same known state and random streams;
- compare outcomes.

Do not claim mathematically complete causal counterfactuals. Present them as branch simulations.

## 10. Run comparison

Compare two deterministic runs:

- first divergent tick;
- different program package hashes;
- changed observations;
- changed branch or score;
- changed intention;
- changed physical outcome;
- changed mission result.

A useful view:

```text
Run A                           Run B
---------------------------------------------------------
Target E4 score: 0.61           Target E4 score: 0.42
Cover C7 score: 0.48            Cover C7 score: 0.73
Action: Engage E4               Action: TakeCover C7
Outcome: Medic exposed          Outcome: Medic preserved
```

## 11. Data retention

Trace volume can grow quickly.

Use:

- ring buffers during live missions;
- configurable full-trace windows;
- summary traces for all entities;
- compression;
- deduplicated value storage;
- source and package hashes;
- periodic snapshots.

Replay files may optionally omit full traces and regenerate them by authoritative rerun.

## 12. Explainability principles

- Never invent a cause not present in recorded data.
- Distinguish direct cause, contributing condition, and correlation.
- Label uncertainty.
- Preserve the difference between program decision and physical result.
- Show the observations available at the time, not later omniscient state.
- Avoid overwhelming the player with raw event dumps.
- Default to one concise explanation with expandable detail.

## 13. MVP debugger acceptance criteria

For one selected injury in the vertical-slice mission, the player can:

- scrub to the relevant time;
- see the responsible operative’s observation;
- see the selected behaviour and rejected alternatives;
- jump to the exact source expression;
- see the emitted intention;
- see why the physical outcome differed from the intended result;
- edit the doctrine;
- rerun from the same initial seed;
- compare the resulting divergent decision.
