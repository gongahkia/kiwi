# Tikrit

A compact Love2D raycast survival prototype about escaping hostile generated decks with one clear rule: find the exit key, reach the exit shaft, and do it before the one-minute loop runs out.

Each run generates three connected decks with halls, annexes, locked shortcuts, hazards, tool caches, shelters, NPC guides, creature nests, and readable ecology signs. The game is intentionally immediate: no terminal commands, no relay checklist, no codex screen, and no route-management layer between decks.

## Core Loop

- You have 60 seconds on each life.
- Getting caught or running out of time wakes you back at the current shelter.
- Keys and opened routes persist on the deck, so each loop should push a little farther.
- The exit key opens the deck exit. Small keys open nearby locked shortcuts with `F`.
- Shelters set your wake point and refill the timer when you step onto them.
- NPC guides give practical local information: exit direction, nearest key, shelter, threat behavior, terrain pressure, and tool cache hints.

## Reading The Area

- Terrain changes speed and noise. Water, rubble, grates, moss, slag, wire, ember lanes, and ladders all matter.
- Creatures react to sound, sight, scent, light, signals, props, nests, and each other.
- Tracks, scratches, nest debris, wet marks, ash drift, vent calls, alarm marks, trade marks, and pheromone boundaries teach predator/prey relationships in-world.
- Survey probes reveal more recent signs but do not freeze the game or give exact creature positions.
- Tool caches can be real or mimics. NPCs, probes, and cautious observation help separate them.

## Diegetic Map

Hold `M` to look down at the handheld map. On gamepad, hold `Back`.

The map does not pause the game. It shows remembered floor space, nearby known cells, keys, shelters, locks, caches, NPCs, signs, and close creature pressure only when that information has been observed. You can keep moving while looking at it, but it costs attention.

## Ecology

- Hunter: apex predator that tracks player noise and weaker prey.
- Stalker: dark ambusher that avoids strong light and flares.
- Skitter: prey thief that panics loudly and steals useful objects.
- Screecher: sound predator that follows loud stimuli and disrupts hunts.
- Burrower: territorial nest guard that favors rubble and flooded routes.
- Mimic: false cache predator exposed by proximity, survey pulses, or careless looting.

## Controls

- `WASD`: move and strafe
- `Mouse`, `Left`/`Right`, `Q`/`E`: turn
- `Shift`: sprint
- `F`: talk to a nearby NPC guide or open a nearby locked shortcut
- `M`: hold the handheld map
- `H`: hold the status readout
- `Tab`: cycle field tools
- `1`-`8`: select field tools
- `Space`: use selected field tool
- `X`: cycle render mode: normal, CRT, monochrome dither
- `N`: generate a new run
- `R`: replay current seed
- `F2`: enter/replay a seed
- `Esc`: pause/settings
- Gamepad: left stick move, right stick turn, `A` use tool, `X` interact, shoulders cycle tools, hold `Back` for map, hold `Y` for status, `Start` pause

Conversation screen: `Up`/`Down` select topic, `Enter` ask, `F`/`Esc` close. Gamepad uses d-pad/shoulders, `A`, and `B`/`X`.

## Tools

- Flares reveal local space, repel stalkers, and attract sight/sound predators.
- Noisemakers lure hunters and screechers away.
- Scent markers create a fake player trail.
- Snare wires slow one creature, then break loudly.
- Pheromone vials create false territory boundaries that predators hesitate to cross.
- Survey probes reveal recent tracks and signs.
- Oil kits refill torch fuel.
- Lure beacons create loud cache marks that pull skitters, screechers, and curious hunters.

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
