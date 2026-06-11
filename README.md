# Tikrit

A compact Love2D prototype: a Doom-style raycast survival game where a small procedural ecology hunts, flees, scavenges, and reacts while the player moves through freshly generated decks of a megastructure.

Every run generates three connected flat decks of large halls, themed rooms, annexes, columns, sealed shortcuts, locked connectors, computer terminals, hazards, salvage rooms, creature lairs, vents, hybrid districts, ecology signals, and ladder-shaft landmarks. The renderer stays in the old-school 2.5D style while keeping one floor and one ceiling plane.

Traversal is the focus: terrain can be rubble, water, moss, grates, catwalks, glass, slag, hazards, or ladder shafts. Different surfaces change movement speed and noise, keys open locked shortcuts, relays provide reroutable power, terminals control deck systems, and tools let the player redirect rather than fight threats.

Survive escalating deck cycles, route enough power to authorize the lift, and reach the exit shaft before the ecology collapses around you. Full relay completion leaves more salvage available; early lift authorization can seal optional salvage. Between decks, choose a descent route that changes the next biome, faction pressure, incidents, and salvage rewards.

## Systems

- Relays grant power units.
- Terminals route power to lights, doors, pumps, vents, decoy, and lift systems.
- Lights improve visibility and torch economy, but make sight hunters stronger.
- Doors open sealed shortcuts while powered.
- Pumps suppress wire/ember hazards and weaken burrowers.
- Vents support purging and noise transmission.
- Decoy power emits periodic fake-player noise and drains torch fuel.
- Lift power enables extraction after the minimum relay threshold.

## Living Megastructure

- Each deck runs through survival-cycle phases: quiet, warning, surge, collapse, and aftermath.
- Cycle phases trigger biome-specific incidents: blackout, flood surge, vent bloom, heat spike, lockdown, nest wake, or faction raid.
- Incidents create readable signs, terminal logs, noise, alarms, temporary route changes, and hazard pressure.
- Shelter marks identify temporary pockets that reduce cycle pressure during surge/collapse windows.
- Survey probes reveal recent signs without showing exact creature positions.
- Local achievement hooks record major discoveries and extraction, but demo mode disables unlocks.

## Branch Routes

- Extraction now opens a route-selection screen instead of immediately loading the next deck.
- Route types are safer route, rich salvage, and faction conflict.
- Choices show biome, risk, salvage promise, and unlocked previews for faction or incident pressure.
- Salvage unlocks future variety: starting probe, pheromone, breaker, route previews, and rare cache signals.
- Unlocks are variety-only. There are still no combat, health, damage, or speed upgrades.

## Industrial Underworld Biomes

- Cryo vaults add freezing fog, ice surfaces, frost traces, brittle seals, and breaker-thaw shortcuts.
- Fungal service tunnels add spore blooms, scent confusion, amplified pheromones, and skitter pressure.
- Pressure labs add pressure ticks, alarm seals, glassy sight-line pressure, and route-control decisions.
- Reactor trenches add radiant heat, fuse overcharge, ember pressure, and sonic/screecher panic.
- Waste arteries add sludge, pump dependency, tainted salvage, and burrower/skitter pressure.
- Storm drains add flood cycles, surge lines, live conduits, leechers, valves, and grounding spike routes.
- Ash foundries add smoke veils, heat shelters, coolant play, slag pressure, and choir/screecher sound loops.
- Signal catacombs add false pings, mimic caches, survey counterplay, and warden infrastructure guards.
- Bone markets add trade marks, scavenger rivals, baited salvage, and faction raid pressure.
- Organ machines add living doors, pulse marks, coolant counters, warden patrols, and biological alarms.

## Districts

- Collapsed caves add rubble loops, dark pockets, and burrower routes.
- Flooded basins add water, wire hazards, and pump-sensitive crossings.
- Machine mazes add grates, vents, sound paths, and screecher pressure.
- Foundry arenas create exposed predator crossings.
- Salvage vaults hold optional tools and can be sealed by early lift authorization.
- Nest zones mark creature homes, hoards, and raid targets.

## Ecology

- Hunter: apex predator that tracks player noise and weaker creatures.
- Stalker: dark ambusher that avoids strong light and flares.
- Skitter: scavenger prey that can steal carried supplies and panic loudly.
- Screecher: sound predator that follows loud stimuli and disrupts hunts.
- Burrower: territorial hazard-creature weakened by pumps.
- Warden: infrastructure guard that reacts to terminals, powered doors, and lift systems.
- Leecher: flooded-route predator repelled by grounding spikes and pressure control.
- Mimic: false signal/cache predator exposed by proximity, survey pulses, or careless looting.
- Choir: vent-linked sound predator that becomes more dangerous during blooms and blackouts.
- Scavenger rival: nonlethal thief that steals exposed caches or carried salvage and flees.
- Creatures guard nests, raid weaker nests, steal props, hoard supplies, follow tracks, react to pheromones, and respond differently to tools and incidents.
- Tracks, scratches, nest debris, wet marks, ash drift, vent calls, alarm marks, and pheromone boundaries teach the ecology in-world.
- Nests now belong to factions such as scavenger, predator, machine-nest, burrow colony, and screeching flock.
- Salvage theft, seals, pheromones, bait, and incidents raise faction alarms and can trigger cross-faction raids.

## Run

```sh
make run
make demo
```

## Validate

```sh
make test
make validate
make validate-deep
lua tools/validate_levels.lua 200 1 all 32
```

## Controls

- `WASD`: move and strafe
- `Mouse`, `Left/Right`, `Q/E`: turn
- `Shift`: sprint
- `F`: use nearby terminal
- `Tab`: cycle all field tools
- `1`-`9`, `0`, `-`, `=`, `Backspace`: select the first thirteen field tools while playing
- `Space`: use selected field tool while playing
- Route screen: `1`-`3`, arrows, `Tab`, or `Enter` choose the next descent route.
- `C`: toggle persistent codex
- Ladder shafts mark exits and shortcut areas
- `M`: toggle minimap
- `N`: generate a new structure
- `R`: replay current seed
- `F2`: enter/replay a seed
- `X`: toggle post-process shader
- `Esc`: pause/settings. Use `Up`/`Down`, `Enter`, and `Backspace` to rebind/reset saved controls.
- Gamepad: left stick move, right stick turn, `A` use tool/confirm route, `X` terminal, `Y` codex, shoulders cycle tools/routes, `Back` map, `Start` pause.

## Terminals

- `SCAN`: reveal terminal nodes on the map
- `UNLOCK`: open a linked sealed route
- `PURGE`: run local pump/vent hazard control
- `1`/`LIGHTS`: toggle lights
- `2`/`DOORS`: toggle powered doors
- `3`/`PUMPS`: toggle pumps
- `4`/`VENTS`: toggle vents
- `5`/`DECOY`: toggle decoy pulse
- `6`/`LIFT`: toggle lift authorization when enough relays are online

## Tools

- Flares reveal map space, repel stalkers, and attract sight/sound predators.
- Noisemakers lure hunters and screechers away.
- Bait redirects or feeds predators, but can alarm nests.
- Scent markers create a fake player trail.
- Sonic stakes pull screechers and can trigger predator collisions.
- Flash pods panic skitters/stalkers and disrupt sight pressure.
- Snare wires slow one creature, then break loudly.
- Fuses add temporary power.
- Seal charges close a nearby route temporarily.
- Pheromone vials create false territory boundaries that predators hesitate to cross.
- Breaker plugs safely cut one nearby powered subsystem, then restore it after pressure bleeds out.
- Survey probes reveal recent tracks and signs without exposing exact creature locations.
- Oil kits refill torch fuel.
- Valve cranks redirect flood pressure and briefly calm live water routes.
- Grounding spikes suppress nearby wire hazards and repel leechers.
- Smoke charges break sight lines but carry noise through vents.
- Lure beacons create loud salvage marks that pull scavengers and sound predators away.
- Coolant ampoules suppress ember lanes and slow wardens or mimics caught nearby.

## Codex

The codex records discovered creatures, districts, nests, incidents, signals, tools, and interaction rules through `love.filesystem` under the `tikrit` identity. Settings and local achievement hooks use the same save area. Progression remains knowledge-only; there are no persistent upgrades.
