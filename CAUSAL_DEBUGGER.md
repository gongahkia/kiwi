# Causal Debugger Specification

## 1. Purpose

The causal debugger is the main differentiator of Kiwi. It explains how program logic, incomplete information, simulation rules, and adversarial events combined to produce an outcome.

It must not pretend every consequence has one cause. It should expose a structured causal chain with decisive and contributing factors.

## 2. User questions

The debugger must eventually answer:

- Why did this operative move here?
- Why did it choose this target?
- Why did it not take available cover?
- Why was an ally not stabilised?
- Why did this intention fail?
- Which information was stale or uncertain?
- Which source expression emitted the intention?
- Which priority or threshold decided among alternatives?
- What physical event caused this injury?
- What changed between two policy versions or runs?

## 3. Causal model

A typical chain is:

```text
world evidence
 -> observation value
 -> expression evaluation
 -> branch or match selection
 -> intention construction
 -> validation and arbitration
 -> simulation action
 -> physical event
 -> tactical consequence
```

Chains may merge and branch. An injury may depend on the operative’s movement decision, an enemy fire decision, cover geometry, projectile dispersion, and timing. A
projectile retains its exact Fire intention ID, invocation ID, expression ID,
source span, policy-list index, and creation tick through impact and injury,
so physical consequences stay source-addressable after later ticks.

## 4. Stable identifiers

Use stable IDs for:

- invocation;
- expression;
- evaluation record;
- observation fact;
- intention;
- validation;
- arbitration;
- event;
- consequence;
- trace edge.

IDs are local to a run unless content-derived identity is useful.

### 4.1 Trace packet version 1

`KWI-TRACE\0` version `1` stores one immutable trace graph tied to an exact
canonical run-state hash. It has an explicit trace level, node-ID-ordered typed
records, and edge-ID-ordered typed graph links. The initial packet has no
chunking, compression, interning, retention window, or query cache; those are
later storage concerns. Decoders reject unsupported, malformed, duplicate-field,
oversized, and noncanonical packets rather than repairing or reinterpreting
them. Trace capture and trace hashes remain outside authoritative state.

## 5. Trace records

### 5.1 Policy invocation

```text
PolicyInvocation {
  id
  tick
  entity_id
  policy_id
  bytecode_hash
  entry_point
  observation_id
  input_memory_hash
  result_kind
  cost
  trace_level
}
```

### 5.2 Expression evaluation

```text
ExpressionEvaluation {
  id
  invocation_id
  expression_id
  source_span_id
  kind
  value_summary
  input_evaluation_ids
  observation_fact_ids
  cost
}
```

### 5.3 Observation fact

```text
ObservationFact {
  id
  observation_id
  path
  value_summary
  evidence_event_ids
  confidence
  age
}
```

Contact observations resolve each policy-relevant field to its retained ordered
evidence event IDs. A trace records `OBSERVED_FROM` edges for direct sensor
evidence and `DERIVED_FROM_MESSAGE` edges when later message delivery contributes
to a field. A message delivery event has its send event as sole parent, and the
send event parents the message's ordered source evidence. Contact decay preserves
the original evidence links while age and confidence change under documented
deterministic rules.

### 5.4 Intention origin

```text
IntentionOrigin {
  intention_id
  issuer_entity_id
  invocation_id
  source_expression_id
  source_span
  policy_order
  creation_tick
  kind
  action_channel
}
```

### 5.5 Resolution record

```text
IntentionResolution {
  intention_id
  status
  reason_code
  competing_intention_ids
  world_event_ids
}
```

The canonical event stream represents the initial policy chain as a
`policy_evaluated` event, an `intention_emitted` child for each candidate, and
one `intention_selected` or `intention_rejected` child of that candidate. The
candidate retains its full `IntentionOrigin`; a rejection retains its stable
reason and competing intention IDs.

When policy validation fails, the corresponding `policy_evaluated` event
retains the structured failure and its resolved decision is a `hold` fallback:
the input memory persists and no candidate is emitted.

### 5.6 Consequence record

```text
Consequence {
  id
  kind
  tick
  subject_ids
  event_id
  severity
  summary_fields
}
```

### 5.7 Edge

Edges use typed reasons:

- `READ_FROM`;
- `COMPUTED_FROM`;
- `SELECTED_BRANCH`;
- `CONSTRUCTED`;
- `VALIDATED_BY`;
- `REJECTED_BECAUSE`;
- `SELECTED_OVER`;
- `CAUSED_EVENT`;
- `CONTRIBUTED_TO`;
- `OBSERVED_FROM`;
- `DERIVED_FROM_MESSAGE`.

## 6. Trace levels

### 6.1 Off

Only replay and canonical simulation events. Not suitable for explanation.

### 6.2 Summary

Retain policy invocation, selected branches at labelled decision points, emitted intentions, resolution, major events, and consequences.

### 6.3 Decision

Retain all branch and match selections, decisive values, observation reads that influenced decisions, intention candidates, and resolution records.

### 6.4 Full

Retain expression-level evaluations, value summaries, call structure, and detailed provenance. Used for fixtures and debugging, not default long missions.

## 7. Instrumentation strategy

The compiler inserts or associates stable expression IDs. The VM records evaluations according to trace mode. Standard-library intrinsics report semantic trace events instead of appearing as opaque Python calls.

The current VM boundary exposes opt-in execution-order `TraceExpression`
source-map entries and observation `LoadField` records on each `VMRunResult`.
Each observation record retains its source-map entry, canonical path, closed
value, ordered evidence event IDs, and applicable contact confidence and age.
It also records only the executed `then` or `else` conditional arm and `Some`
or `None` Option-pattern arm. Standard-library capture records `List.filter`
retained source indices, `List.find` and `List.min_by` selected source indices,
and `List.sort_by` ranking source-index order, with each intrinsic's input and
callback-evaluated counts; that switch also enables detailed Cover candidate
capture. `PolicyEvaluation` already retains the allocated policy invocation ID,
so its caller can join every stream to one exact policy invocation without
changing authority state, IDs, values, or fault behaviour. Input-only metadata
is stripped from top-level VM results. Later trace capture converts these
boundary records into the versioned graph packet.

Examples:

- `Threat.score` reports its principal inputs and output.
- `List.min_by` reports its selected source index and evaluated candidate count;
  equal keys retain the earliest input index.
- `Cover.nearest_safe` reports every candidate's exposure and route-cost score,
  first losing rank component, and selected slot from its source-mapped call.

Avoid recording irrelevant arithmetic noise at summary levels.

## 8. Explanation queries

### 8.1 Why was an intention selected?

Return:

- source location;
- selected branch path;
- decisive observation values;
- candidate order;
- validation result;
- relevant standard-library decisions.

### 8.2 Why was an intention not selected?

Return one or more:

- never constructed due to branch;
- constructed but later in policy order;
- failed capability validation;
- incompatible action channel already occupied;
- target invalidated;
- action interrupted before completion.

The query must distinguish “the program did not request it” from “the simulation rejected it.”

### 8.3 Why did an intention fail?

Follow from intention through resolution events. Examples:

- cover occupied first;
- route blocked;
- weapon empty;
- target estimate stale;
- operative suppressed;
- projectile hit cover;
- action interrupted by injury.

### 8.4 Why was information wrong?

Show:

- source sensor or message;
- observation tick;
- confidence and age;
- update or decay rules;
- true world state only in post-mission analysis or authorised modes.

### 8.5 Why did this consequence happen?

Return a ranked causal subgraph:

- direct physical cause;
- subject’s decisive policy cause;
- adversary cause;
- information limitations;
- deterministic random draw if material;
- contextual contributing factors.

Ranking is explanatory, not metaphysical certainty. Label heuristics as such.

## 9. Source integration

The debugger must navigate from trace records to:

- source module;
- line and column;
- highlighted expression;
- enclosing function;
- policy version;
- rendered value summaries.

If source has changed since the run, display the historical source associated with the bytecode hash. Do not highlight current source against an old source map.

## 10. Timeline UI contract

The timeline groups events by tick and category:

- observation;
- policy;
- communication;
- movement;
- combat;
- injury;
- objective;
- system fault.

Selecting an event displays:

- concise description;
- entity and location;
- causal parents;
- causal children;
- source link where available;
- related alternatives;
- run-comparison status.

## 11. Run comparison

Compare runs only when a meaningful common baseline exists, such as same mission content and initial seed.

Comparison should identify:

- policy and parameter differences;
- first divergent policy evaluation;
- first divergent intention;
- first divergent authoritative state checkpoint;
- changed consequences;
- identical outcomes reached by different paths.

Do not imply that later differences have a single cause after large divergence. Highlight the first known divergence and relevant downstream chains.

## 12. Counterfactual support

MVP counterfactuals are controlled reruns, not fabricated predictions.

A valid counterfactual:

- restores a canonical snapshot;
- changes a policy bundle or permitted parameter;
- uses the same remaining command log and seed manifest where valid;
- reruns authority;
- compares traces.

Do not alter one internal branch result without re-executing the simulation.

## 13. Retention

Trace storage can be bounded by:

- ring buffers;
- key-event bookmarks;
- summary compaction;
- value interning;
- source-span interning;
- periodic canonical snapshots;
- on-demand deterministic re-execution.

Runs used for comparison should retain enough inputs to reproduce discarded detail.

## 14. Privacy and safety of debug values

Policies operate only on game data, so sensitive external data is not expected. Nevertheless, trace formats should avoid arbitrary Python object serialisation and should store only closed validated values.

## 15. Explainability principles

- Separate code choice from world outcome.
- Show uncertainty explicitly.
- Show rejected alternatives when available.
- Prefer source expressions and domain values over VM instructions.
- Avoid false certainty.
- Keep concise summary available, with expandable detail.
- Preserve historical source.
- Make deterministic random draws visible when decisive.

## 16. MVP causal fixture

A required test fixture contains:

- an operative;
- visible cover;
- a hostile contact;
- a policy danger threshold;
- an advance branch;
- an enemy shot;
- an injury.

The debugger must return a chain from the threshold literal or comparison through the movement intention to the injury, while also showing the enemy fire and projectile impact as direct physical causes.

## 17. Acceptance criteria

- Major consequences have structured causal parents.
- Queries distinguish absent, rejected, interrupted, and failed intentions.
- Source navigation works for historical bytecode.
- Full and summary traces agree on high-level explanation.
- Run comparison finds the first divergence in known fixtures.
- Trace capture does not change authoritative hashes.
- Trace formats are versioned and validated.
