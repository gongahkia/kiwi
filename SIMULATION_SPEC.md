# Deterministic Simulation Specification

## 1. Scope

This document defines the authoritative real-time simulation contract for Doctrine.

The simulation must support:

- autonomous squad behaviour;
- physical movement and projectiles;
- cover and line of sight;
- incomplete perception;
- communication latency;
- damage and suppression;
- mission objectives;
- deterministic replay;
- causal event recording.

## 2. Time model

### 2.1 Fixed timestep

The authoritative simulation advances in fixed ticks.

Rendering frame rate must not affect authoritative results.

Recommended initial rates:

- physics: 60 Hz;
- policy evaluation: 10–20 Hz depending on responsiveness and performance;
- perception refresh: configurable by sensor;
- communication delivery: tick scheduled;
- rendering: uncapped or display-synchronised.

The exact values should be measured and pinned in configuration.

### 2.2 Simulation time

Use integer ticks as the canonical time representation.

Durations convert to ticks through validated deterministic rules.

Avoid using host wall-clock time inside simulation logic.

## 3. Determinism contract

The initial guarantee is:

> Given the same build, pinned dependencies, mission content, initial snapshot, program packages, tactical input stream, and seeds, the authoritative simulation produces the same canonical state hashes and event sequence on supported environments.

Required practices:

- deterministic system order;
- stable entity ordering;
- deterministic random streams;
- no unordered table iteration;
- fixed numeric policy;
- controlled physics configuration;
- explicit tie-breakers;
- versioned content and bytecode;
- periodic state hashing.

Cross-platform bit-identical physics may not be realistic immediately. Detect divergence and constrain the supported determinism claim rather than pretending it does not exist.

## 4. Entity model

Entities have stable IDs and composable components.

Representative components:

- Transform
- PhysicsBody
- Operative
- Health
- Injury
- Mobility
- SensorSuite
- ContactTracker
- Communication
- Equipment
- Weapon
- Ammunition
- Suppression
- DoctrineBinding
- ProgramMemory
- IntentQueue
- Assignment
- Faction
- ObjectiveParticipant
- Cover
- Projectile
- Destructible

Structural changes are queued and applied at a deterministic phase boundary.

## 5. Observation cycle

For each policy evaluation:

1. Determine sensor updates due this tick.
2. Perform permitted spatial and visibility queries.
3. Update contact tracks.
4. Deliver messages scheduled for this tick.
5. Assemble immutable observation values.
6. Sort all collections deterministically.
7. Assign an observation ID and hash.
8. Invoke the program.

Observation history may be bounded and retained for debugging.

## 6. Perception

### 6.1 Visibility

Visibility depends on:

- sensor range;
- line of sight;
- stance;
- cover and obstruction;
- lighting or environmental modifiers where implemented;
- target movement or signature;
- sensor damage.

### 6.2 Tracks

A track is an estimate, not authoritative entity state.

Track updates may:

- improve confidence;
- increase confidence radius precision;
- decay over time;
- extrapolate velocity;
- merge or split uncertain contacts;
- retain a last-known position.

The MVP can use a simpler model, but must retain timestamps and confidence.

### 6.3 Information provenance

Every track field should record enough provenance to answer:

- whether it was directly observed;
- whether it came from an ally;
- when it was observed;
- how stale it is;
- which sensor produced it.

## 7. Communication

Messages are typed values.

A message lifecycle:

1. Program emits `Emit` intent.
2. Resolver validates channel and payload.
3. Communication system determines recipients.
4. Delivery tick is scheduled.
5. Failures or drops are recorded.
6. Recipient observation includes delivered message.

Messages have:

- stable ID;
- sender;
- recipients or audience selector;
- channel type;
- payload;
- sent tick;
- delivery tick;
- expiry tick;
- reliability metadata.

## 8. Intent lifecycle

### 8.1 Creation

The VM returns an ordered list of intentions. Each receives:

- stable intent ID;
- source evaluation ID;
- source expression ID;
- requested priority;
- creation tick.

### 8.2 Validation

Validate:

- schema;
- capability;
- target form;
- current actor state;
- resource availability;
- mutually exclusive actions;
- timing.

### 8.3 Arbitration

When several intentions conflict:

- use explicit category rules;
- use declared or derived priority;
- use stable tie-breakers;
- emit rejection reasons for losing intentions.

### 8.4 Execution

Accepted intentions create lower-level action state.

Examples:

- movement controller target;
- aim controller target;
- weapon firing request;
- medical action timer;
- breach action timer;
- message transmission.

### 8.5 Outcome

Every intention ends in an outcome:

- completed;
- failed;
- interrupted;
- superseded;
- expired;
- cancelled;
- still active.

Outcome records link to physical and logical causes.

## 9. Movement

Movement should model:

- acceleration;
- maximum speed;
- stance-dependent speed;
- turning;
- collision;
- path constraints;
- dynamic obstacle avoidance;
- arrival tolerance;
- cover occupancy.

Pathfinding may produce a planned route, but local physical movement can deviate.

A movement intent may fail because:

- route unavailable;
- route invalidated;
- collision;
- suppression;
- injury;
- occupied destination;
- higher-priority action;
- physical displacement.

## 10. Cover

Cover is represented by physical geometry and semantic cover points.

A cover point contains:

- position;
- normal or protected direction;
- supported stances;
- occupancy;
- structural integrity;
- adjacent movement anchors;
- relevant geometry ID.

The physical geometry remains authoritative for projectile collision. Cover-point metadata exists to help doctrine reason efficiently.

## 11. Aiming and firing

### 11.1 Aim state

An operative has:

- current facing;
- desired aim direction;
- stabilisation error;
- weapon readiness;
- movement penalty;
- suppression penalty;
- injury modifiers.

### 11.2 Fire request

A fire intent specifies a target estimate, not necessarily an authoritative entity.

The resolver:

- validates weapon state;
- selects aim point;
- applies deterministic spread based on a scoped random stream;
- spawns a physical projectile;
- records all inputs.

### 11.3 Randomness

Randomness must be explicit and replayable.

Use independent streams for:

- weapon spread;
- perception noise;
- environmental variation;
- content generation;
- AI or doctrine only where an explicit random value is provided as observation data.

User programs cannot request arbitrary hidden randomness in the MVP.

## 12. Damage and injury

Damage pipeline:

1. Collision or impact event.
2. Determine impacted body and material.
3. Compute simplified energy or damage transfer.
4. Apply armour or cover effects.
5. Update health or component integrity.
6. Determine injury state.
7. Emit canonical events.
8. Update observations on later ticks.

The MVP can use simplified values while preserving explicit event provenance.

## 13. Suppression

Suppression accumulates from:

- nearby projectile paths;
- impacts;
- explosions;
- observed casualties;
- hostile proximity.

It decays over time.

Suppression is represented as explicit state and included in observations.

## 14. Medical actions

States:

- healthy;
- injured;
- critical;
- incapacitated;
- stabilised;
- dead or lost, depending on tone.

A stabilisation intent requires:

- valid equipment;
- proximity;
- uninterrupted action duration;
- viable target state.

## 15. Mission objectives

Objectives are deterministic state machines.

Examples:

- reach region;
- hold region for duration;
- escort entity;
- retrieve object;
- stabilise target;
- extract minimum squad members;
- prevent destruction;
- survive until time.

Objective transitions emit events and are included in replay hashes.

## 16. State hashing

Canonical state hash includes:

- tick;
- entity IDs and serializable components in stable order;
- mission objective state;
- random stream states;
- pending messages;
- pending intentions;
- active projectiles;
- program memory;
- relevant physics state;
- tactical signal queue.

Exclude presentation state.

## 17. Snapshots

Snapshots support:

- replay seeking;
- divergence diagnosis;
- branch simulation;
- tests;
- crash recovery.

Snapshots must be versioned and validated.

## 18. Headless mode

The full authoritative simulation must run without rendering, input, or audio.

Headless runner inputs:

- mission definition;
- program packages;
- initial seed;
- tactical signal script;
- maximum ticks;
- trace mode.

Outputs:

- result;
- objective status;
- casualty summary;
- event log;
- state hashes;
- optional replay;
- optional trace bundle.
