# Game Design Specification

## 1. Design statement

Doctrine is a real-time squad tactics game in which the player designs decision-making systems rather than issuing individual tactical actions.

The player should feel responsible for outcomes without having omniscient control over them. Good play means designing robust doctrine that handles uncertainty, not memorising a level script or repeatedly pausing to optimise each move.

## 2. Comparison boundary

The game borrows from XCOM-like structures:

- mission briefings;
- persistent operatives;
- squad composition;
- equipment loadouts;
- injuries and recovery;
- cover-based tactical spaces;
- fog of war;
- extraction and objective pressure;
- post-mission consequences.

It deliberately does not copy:

- turn-by-turn action-point control;
- percentage-to-hit as the primary combat abstraction;
- direct selection and command of individual operatives;
- class abilities as fixed button bars;
- unrestricted tactical save-scumming.

## 3. Core loop

1. Receive a mission with incomplete intelligence.
2. Select operatives and equipment.
3. Configure or edit squad doctrine.
4. Compile and review diagnostics.
5. Run short deterministic tests where permitted.
6. Deploy.
7. Issue limited high-level tactical signals.
8. Observe autonomous execution.
9. Complete, fail, abort, or extract.
10. Review the causal timeline.
11. Update doctrine and squad configuration.
12. Continue the campaign or rerun a training branch.

## 4. Mission structure

### 4.1 Briefing data

A mission definition provides:

- map seed or authored map ID;
- visible deployment regions;
- primary objective;
- optional objectives;
- extraction rules;
- mission timer or escalation model;
- expected threat categories;
- intelligence confidence;
- communication environment;
- environmental rules;
- permitted equipment;
- squad size.

### 4.2 Mission phases

#### Deployment

- Select insertion region.
- Assign operatives to fireteams or roles.
- Select doctrine version.
- Apply parameters.
- Review capability warnings.

#### Infiltration

- Limited enemy knowledge.
- Emphasis on movement, visibility, sound, and spacing.
- Initial signals define broad approach.

#### Contact

- Doctrine reacts to threats.
- Target ownership, cover, suppression, and communication become important.

#### Objective execution

- Rescue, capture, retrieve, plant, defend, investigate, or escort.
- The squad must balance objective urgency and survival.

#### Extraction or consolidation

- Squad withdraws, secures a region, or waits for a condition.
- Injured operatives may need assistance.
- Aborting remains a valid strategic outcome.

## 5. Player control model

### 5.1 Prohibited direct commands

The player cannot directly issue:

- move to exact tile;
- shoot this target;
- use this item now;
- enter overwatch now;
- heal this ally now;
- breach this exact wall now.

### 5.2 Allowed tactical signals

Signals are values consumed by doctrine:

```text
AdvanceTo Region
Hold Region
Prioritise ObjectiveId
Avoid Region
ExtractAt Position
Abort
```

A signal has:

- sender;
- timestamp;
- target audience;
- payload;
- delivery status;
- latency;
- expiry.

A doctrine may ignore, delay, reinterpret, or reject a signal according to its logic and available information.

### 5.3 Why signals exist

Without any live input, the mission risks becoming a passive simulation. Signals preserve strategic participation while ensuring that the doctrine remains responsible for tactical execution.

## 6. Operatives

### 6.1 Operative data

Each operative has:

- stable ID;
- callsign;
- body profile;
- mobility characteristics;
- sensor capabilities;
- communication capabilities;
- equipment slots;
- health and injury state;
- stress or suppression state;
- learned capability modules;
- mission history;
- current doctrine assignment;
- local program memory.

### 6.2 Roles

Roles are not hard-coded classes. A role is an assignment produced by squad doctrine based on capabilities and mission state.

Examples:

- scout;
- point;
- support;
- medic;
- breacher;
- marksman;
- carrier;
- rear guard.

The same operative can receive a different role in another mission.

### 6.3 Persistence

Persistence should create meaningful constraints rather than numerical grind.

Operatives may gain:

- access to specialised equipment;
- improved sensor interpretation;
- lower action latency for familiar tools;
- new message schemas;
- additional memory budget;
- trusted doctrine modules;
- recovery needs after injury.

Avoid simple permanent stat inflation where possible.

### 6.4 Injury

Injuries alter explicit capabilities:

- reduced movement speed;
- degraded aim stabilisation;
- limited carrying capacity;
- delayed reaction;
- narrower sensory field;
- inability to use certain equipment.

Doctrine can inspect these states and adapt.

## 7. Combat and physical interaction

### 7.1 Intent-based actions

Programs emit intentions. The world resolves them.

Examples:

- `Move destination stance`
- `TakeCover coverPoint`
- `Aim target`
- `Fire weapon targetEstimate`
- `Use equipment target`
- `Stabilise ally`
- `Breach surface`
- `Emit channel message`
- `Wait duration`

An emitted intention is not guaranteed to succeed.

### 7.2 Projectiles

Projectiles should:

- have travel time;
- collide with world geometry;
- interact with cover;
- apply impact at the actual collision point;
- support penetration or fragmentation at a simplified level;
- record trajectory and collision provenance.

The MVP does not require a high-fidelity ballistic simulator. It requires visible, inspectable causality.

### 7.3 Cover

Cover is geometry, not merely a tile flag.

Cover provides:

- occlusion;
- protection from projectile paths;
- posture-dependent exposure;
- destructibility;
- occupancy constraints;
- pathing consequences.

Cover selection functions should reason about:

- threat direction;
- expected exposure;
- travel time;
- occupancy;
- objective distance;
- escape routes;
- structural integrity.

### 7.4 Suppression

Suppression is an explicit state derived from nearby hostile fire, impact, shock, and perceived danger.

It can influence:

- movement speed;
- aim stability;
- available intentions;
- confidence estimates;
- action delay;
- doctrine branch selection.

Suppression must be observable and traceable, not a hidden debuff.

## 8. Information model

### 8.1 No omniscient world state

An operative observes only what its sensors, allies, and communication network provide.

Observations may be:

- current;
- delayed;
- uncertain;
- partial;
- contradictory;
- stale;
- absent.

### 8.2 Contact estimates

A perceived entity should generally be represented as a track:

```text
Track {
  entityHint,
  estimatedPosition,
  estimatedVelocity,
  classification,
  confidence,
  errorRadius,
  observedAt,
  source
}
```

Programs must decide how to act on imperfect tracks.

### 8.3 Communication

Operatives exchange typed messages.

Communication may fail because of:

- range;
- obstruction;
- interference;
- damaged equipment;
- bandwidth limits;
- recipient unavailability;
- message expiry.

A message is never treated as instantaneous shared state.

## 9. Squad doctrine layers

### 9.1 Squad coordinator

Responsible for:

- assigning roles;
- interpreting player signals;
- selecting broad objectives;
- allocating targets;
- preserving formation constraints;
- coordinating extraction.

Signature:

```text
coordinate : SquadObservation -> DoctrineState
           -> (DoctrineState, List Assignment)
```

### 9.2 Operative policy

Responsible for local action selection.

Signature:

```text
act : OperativeObservation -> OperativeMemory
    -> (OperativeMemory, List Intent)
```

### 9.3 Equipment controllers

Optional specialised functions for:

- grenade throws;
- breaching charges;
- drones;
- medical tools;
- deployable sensors;
- automated weapons.

## 10. Priority and arbitration

A core beginner-friendly pattern is a list of candidate behaviours:

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

The debugger can explain:

- which candidate won;
- why earlier candidates did not apply;
- the values used by the winning candidate;
- whether the intention later failed physically.

This pattern should form the basis of early onboarding.

## 11. Mission archetypes

### Rescue

- Locate civilians or operatives.
- Stabilise and escort them.
- Avoid collateral damage.
- Manage multiple extraction priorities.

### Retrieval

- Find and carry an object.
- Weight and handling affect movement.
- The squad must protect carriers.

### Breach and clear

- Select entry points.
- Coordinate timing and target ownership.
- Avoid clustering and crossfire.

### Hold and defend

- Allocate sectors.
- Reposition as cover degrades.
- Manage ammunition and casualty evacuation.

### Reconnaissance

- Maximise information while minimising detection.
- Place sensors and maintain communication.
- Decide when information is sufficient.

### Sabotage

- Reach and disable infrastructure.
- Handle alarms, reinforcements, and timed escape.

### Extraction under pressure

- Preserve the squad rather than eliminate all threats.
- Decide when to abandon optional objectives.

## 12. First vertical-slice mission

### Working mission: Glasshouse

An abandoned research office contains one trapped technician and a hostile security pair.

Player squad:

- four operatives;
- one medic kit;
- one breaching tool;
- two rifle configurations;
- one deployable sensor.

Map elements:

- two possible entry routes;
- several destructible partitions;
- waist-high office cover;
- one hazardous exposed corridor;
- one extraction zone.

Initial provided doctrine has a deliberate flaw:

- all operatives independently prioritise the most visible hostile;
- target ownership is not considered;
- the medic leaves safe support position;
- the rear flank becomes unobserved.

The player should be able to diagnose the failure and add either:

- target ownership;
- role-specific priority;
- exposure-aware scoring;
- support-distance constraints.

The mission proves the core loop when the revised doctrine produces a clear behavioural difference.

## 13. Campaign progression

Progression should primarily unlock expressive possibilities:

- new observation fields;
- new equipment intents;
- new standard-library modules;
- richer message types;
- higher memory or instruction budgets;
- additional test scenarios;
- new deployment strategies.

Avoid overwhelming the player by unlocking several language concepts at once.

Suggested teaching order:

1. constants and booleans;
2. functions;
3. options;
4. pattern matching;
5. lists and scoring;
6. explicit memory;
7. typed messages;
8. role assignment;
9. higher-order composition;
10. custom data types.

## 14. Failure philosophy

A mission failure should answer at least one of these questions:

- Which information was unavailable?
- Which information was stale?
- Which function interpreted it incorrectly?
- Which priority rule selected the wrong action?
- Which physical constraint prevented the correct intention?
- Which communication failure caused inconsistent squad state?
- Which doctrine assumption did the mission violate?

The player must be able to distinguish a software defect from bad intelligence, physical bad luck, and deliberate risk.
