# Game Design Specification

## 1. Design statement

Kiwi is a real-time tactical programming game about designing a squad’s decision system rather than issuing individual actions. It borrows the emotional structure of persistent-squad tactics—preparation, incomplete intelligence, cover, injury, loss, extraction, and adaptation—without copying turn-based command mechanics.

The player’s skill is expressed through:

- modelling tactical priorities;
- handling uncertainty and missing data;
- composing role behaviour;
- designing fallbacks;
- coordinating agents through delayed messages;
- balancing objectives, safety, ammunition, and time;
- debugging failures after deployment.

## 2. Design boundaries

Kiwi is not:

- an RTS where code is optional automation;
- a turn-based game with programmable macros;
- an arena where agents merely execute combat scripts;
- a coding puzzle with predetermined outputs;
- a fully passive simulation;
- a literal military training product.

Kiwi is:

- a small-squad tactics game;
- real-time and autonomous;
- based on incomplete local observations;
- physically legible where outcomes matter;
- deterministic under recorded inputs;
- designed around repeated hypothesis and revision.

## 3. Core loop

```text
Briefing
  -> squad and equipment
  -> kiwi editing
  -> compilation and tests
  -> real-time mission
  -> consequence selection
  -> causal explanation
  -> code revision
  -> controlled rerun or campaign continuation
```

The player should spend meaningful time in both the workbench and the mission view. Neither should feel like a menu attached to the other.

## 4. Mission structure

### 4.1 Briefing

A briefing includes:

- primary objective;
- optional objectives;
- extraction or completion conditions;
- known map regions;
- confidence-rated hostile intelligence;
- civilian or protected-object information;
- environmental constraints;
- time pressure;
- available deployment points;
- permitted tactical signals;
- consequences of aborting.

Intelligence is represented as estimates, not hidden omniscient facts. A contact may include confidence, age, last-known position, estimated role, and source.

### 4.2 Squad assembly

The player selects a small team, initially four operatives. Each operative has:

- stable identifier;
- physical and movement capability;
- health and injuries;
- sensors;
- equipment;
- communication capability;
- available intentions;
- memory schema expected by its policy;
- later, experience and traits.

A role is not a hard-coded class. It emerges from capability and policy. Templates may be labelled scout, medic, breacher, or marksman for usability, but the language sees typed capabilities.

### 4.3 Kiwi bundle

A mission deploys a versioned kiwi bundle containing:

- squad coordinator;
- one or more operative policy functions;
- role assignment functions;
- equipment controller functions where applicable;
- parameter records;
- memory schemas;
- bytecode modules;
- source maps;
- compiler and language versions;
- content capability manifest.

### 4.4 Mission phases

The simulation need not enforce rigid phases, but scenarios commonly move through:

1. deployment;
2. approach or infiltration;
3. first contact;
4. objective execution;
5. response or reinforcement;
6. extraction or consolidation;
7. debrief and analysis.

## 5. Player control model

### 5.1 Prohibited direct actions

The player cannot normally:

- click a destination to move one operative;
- select a target to fire upon;
- directly activate healing or equipment;
- pause and queue exact unit commands;
- drag a formation;
- override a policy branch for one entity.

### 5.2 Permitted high-level signals

A scenario exposes a small typed signal set. Examples:

```text
AdvanceTo RegionId
Hold RegionId
Prioritise ObjectiveId
Avoid RegionId
ExtractAt Position
Abort
```

Signals are appended to the authoritative command log at a specific tick. Policies observe them through an explicit input field. A policy may ignore, delay, reinterpret, or reject a signal according to its code.

### 5.3 Selection and inspection

The player may select entities, contacts, regions, events, and code locations for inspection. Selection must never imply command authority.

### 5.4 Speed and pause

During tutorials and analysis, the player may pause or single-step. Standard missions may allow speed controls but should preserve urgency. Competitive or challenge modes may restrict pausing.

## 6. Operative model

### 6.1 Core state

An operative includes:

- position and facing;
- movement state;
- stance;
- health and body-state abstraction;
- suppression;
- current equipment;
- ammunition and consumables;
- sensor state;
- communication inbox;
- policy memory;
- current and recent intentions;
- policy bundle version;
- objective and role assignments.

### 6.2 Capability model

Policies interact through capabilities rather than concrete class names. Example capabilities:

```text
CanMove
CanTakeCover
CanAim
CanFire(WeaponKind)
CanStabilise
CanBreach
CanObserve(SensorKind)
CanEmit(ChannelType)
```

The compiler rejects intentions unavailable to the entry point’s capability set where statically known.

### 6.3 Persistence

After the vertical slice, operatives may persist across missions with:

- injury recovery;
- equipment familiarity;
- unlocked or changed capabilities;
- recorded mission history;
- configurable policy defaults;
- later, explicit stress-related observation modifiers.

Persistence should increase the cost of poorly designed kiwi without making one failure erase all progress.

### 6.4 Injury and death

The vertical slice requires injury and stabilisation, not detailed anatomical simulation. Injury influences:

- movement;
- aim stability;
- observation reliability;
- action availability;
- extraction urgency.

Death may be deferred until the broader campaign is designed. The causal system must nevertheless support terminal consequences.

## 7. Tactical information

### 7.1 Local observation

An operative does not receive global truth. Its observation is built from:

- own state;
- visible geometry;
- local sensor results;
- remembered contacts;
- received messages;
- assigned objectives and signals;
- nearby ally state where observable;
- known cover and route information.

### 7.2 Contact representation

A hostile estimate should carry data such as:

```text
Contact {
  id
  estimated_position
  position_error
  confidence
  last_seen_tick
  estimated_velocity
  classification
  source_ids
}
```

Policies must pattern-match missing contacts and can reason about confidence and age.

### 7.3 Communication

Communication may be immediate in the earliest prototype, then gain:

- range;
- delay;
- bandwidth;
- message expiry;
- dropped links;
- jamming;
- relays.

Messages are immutable typed values. Shared mutable squad memory is prohibited.

## 8. Tactical actions and intentions

### 8.1 Intent model

Programs emit intentions rather than commands. MVP intentions include:

```text
MoveToward(position, stance)
TakeCover(cover_id, side)
Aim(contact_id or position)
Fire(weapon_id, target_estimate)
Stabilise(ally_id)
Use(item_id, target)
Emit(channel, message)
Wait(duration)
```

The language may present convenience functions, but the core intention set should remain small.

### 8.2 Validation

An intention may be invalid because:

- capability is unavailable;
- target is unknown or stale;
- path or cover no longer exists;
- weapon is empty, cooling, or damaged;
- operative is suppressed or incapacitated;
- instruction is malformed;
- required communication or equipment is missing.

### 8.3 Arbitration

A policy may emit several candidate intentions. The simulation uses documented categories and priorities to select compatible actions. Alternatively, the standard library may require policies to return an ordered plan. The MVP should use one clear model and trace every rejected candidate.

Recommended model:

- policies return an ordered list;
- validation proceeds in order;
- compatible intentions may coexist by action channel, such as movement and communication;
- the first valid intention per exclusive channel wins;
- all decisions are traced.

### 8.4 Physical resolution

Movement, projectile travel, cover impact, explosion radius, and line obstruction should be visibly simulated. Tactical results must not appear as hidden percentage rolls alone.

## 9. Movement and cover

### 9.1 Movement

Movement should account for:

- stance speed;
- acceleration or limited turn rate where useful;
- path geometry;
- operative radius;
- congestion;
- obstacles;
- suppression and injury;
- reserved or predicted cover occupancy.

### 9.2 Cover

Cover is represented through explicit edges or segments with:

- position and normal;
- height class;
- integrity;
- material or resistance class;
- occupancy points;
- exposure directions.

Cover selection should be a standard-library function that advanced players can replace.

### 9.3 Exposure

Exposure is a computed relationship among operative position, stance, cover geometry, hostile estimates, and visibility. The debugger must show which threat estimates contributed to a cover or danger score.

## 10. Aiming, projectiles, damage, and suppression

### 10.1 Aiming

Aim quality evolves over ticks based on:

- weapon handling;
- movement;
- stance;
- suppression;
- injury;
- target estimate error;
- line of sight;
- time spent aiming.

### 10.2 Firing

A fire intention specifies a target estimate or position, not a guaranteed hit. The simulation records:

- aim state;
- deterministic random draw where dispersion is used;
- muzzle position;
- projectile direction and speed;
- ammunition change;
- source intention.

The current generic shot is exact rather than dispersed: an issuer-owned loaded
weapon fires toward a policy-supplied planar position, consumes one round, and
resets aim. The projectile uses a nominal 1,000-millimetre-per-tick direction
and a 30-tick lifetime. Aim is target-free and progresses automatically while
stationary; `Aim {}` reserves the weapon channel without adding another state
transition. Dispersion is later work.

### 10.3 Projectile travel

Projectiles move through the authoritative geometry over fixed ticks. They may hit:

- operatives;
- cover;
- walls;
- doors;
- protected objectives;
- nothing.

### 10.4 Damage

Damage is a deterministic function of projectile state, hit location abstraction, protection, and recorded random draws if variation is retained.

### 10.5 Suppression

Near misses, incoming fire, explosions, and ally injury may increase suppression. Suppression affects movement, aim, and available actions through explicit state visible to the policy.

The current combat slice reduces suppression by 500 basis points each active
tick, applies 1,500 from a non-owner projectile path within two metres, and
applies 2,500 from a non-owner impact within three metres. Path and impact
sources stack to 10,000; direct hits receive the impact source rather than an
additional near-miss source. The new value immediately clamps aim. Movement,
available-action, explosion, and ally-injury modifiers remain later work.

## 11. Squad kiwi layers

### 11.1 Squad coordinator

Conceptual signature:

```text
coordinate : SquadObservation -> SquadMemory
           -> (SquadMemory, List Assignment, List Broadcast)
```

Responsibilities include:

- assigning roles;
- distributing targets;
- designating routes or regions;
- deciding objective priorities;
- requesting extraction;
- coordinating fallback.

### 11.2 Operative policy

Conceptual signature:

```text
step : OperativeObservation -> OperativeMemory
     -> (OperativeMemory, List Intent)
```

Responsibilities include:

- immediate safety;
- movement and cover;
- target selection;
- action choice;
- local communication;
- casualty response.

### 11.3 Equipment controller

Optional specialised functions calculate or filter equipment usage, such as grenade placement or medical triage. They remain pure functions called by operative policy.

## 12. Enemy behaviour

Enemies may initially use project-authored deterministic policies implemented through the same core concepts. They do not need to use player-facing source files in the earliest milestone, but should eventually compile through the same VM where practical to prove symmetry and enable inspectable fixtures.

Enemy AI must not use hidden access to player state beyond scenario-defined observations.

## 13. First vertical-slice mission: Glasshouse

### 13.1 Setup

- Four player operatives.
- Initial roles: Breach (breacher), Mender (medic), Scope (overwatch), and
  Lark (scout), each with a separate bundled DSL policy and magazine loadout.
- Three to five hostiles.
- The initial three hostile roles use the same closed policy concepts as the
  squad: patrol, aim, and hold; they receive no hidden player-state access.
- Compact structure with two entrances.
- Several full and partial cover segments.
- One objective item or protected room.
- One extraction area.
- One 90-second extraction-lockdown event.

### 13.2 Initial flawed kiwi

The provided policy:

- preserves formation too aggressively;
- weights distance to objective too heavily;
- undervalues hostile elevation or crossfire;
- uses a danger threshold that is too permissive;
- causes one operative to advance past viable cover.

### 13.3 Required failure trace

The run produces a chain resembling:

```text
observation: hostile contact confidence 0.78
observation: cover C12 exposure score 0.20
observation: current path exposure score 0.62
source: danger threshold 0.65
branch: continue advance
intention: MoveToward objective
resolution: operative enters hostile line of fire
hostile intention: Fire
projectile: impact operative
consequence: injury and squad delay
```

### 13.4 Revision

The player changes a threshold, weighting function, or priority ordering. The rerun should not necessarily become perfect; it must become visibly and causally different.

### 13.5 Completion

The mission succeeds when the objective is secured and the squad extracts. Optional success measures include casualties, time, ammunition, and policy budget.

## 14. Progression after the vertical slice

Potential progression dimensions:

- new observation fields;
- new capabilities;
- richer message types;
- larger memory records;
- more advanced standard-library functions;
- additional mission archetypes;
- persistent injuries and equipment;
- controlled in-mission deployment;
- policy and replay sharing.

Progression should unlock expressive possibilities rather than merely increase numerical power.

## 15. Mission archetypes

- Rescue under uncertain civilian location.
- Retrieval with weight or carrying constraints.
- Breach with multiple entry policies.
- Hold and defend against timed waves.
- Reconnaissance where information return matters more than combat.
- Sabotage with stealth and delayed triggers.
- Extraction under escalating pressure.
- Escort where the protected entity follows its own policy.
- Communications-denied mission requiring local autonomy.

## 16. Failure philosophy

Failure should be:

- costly enough to matter;
- deterministic enough to investigate;
- complex enough to surprise;
- legible enough to learn from;
- recoverable enough to invite another iteration.

The game should avoid declaring every failure a “coding error.” A policy may be rational under incomplete information and still fail. The debugger must distinguish:

- incorrect code;
- incorrect assumptions;
- stale or missing information;
- physical execution failure;
- adversarial action;
- deterministic uncertainty;
- objective trade-off.
