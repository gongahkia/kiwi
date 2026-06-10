# Tikrit

A compact Love2D prototype: a Doom-style raycast survival game where a pathfinding enemy hunts the player through a freshly generated megastructure.

Every run generates a new connected flat graph of large halls, themed rooms, annexes, columns, sealed shortcuts, and ladder-shaft landmarks. The renderer stays in the old-school 2.5D style while keeping one floor and one ceiling plane.

Traversal is the focus: terrain can be rubble, water, moss, grates, catwalks, glass, slag, or ladder shafts. Different surfaces change movement speed and noise, and sealed shortcuts open once all relays are online.

Survive, activate every relay, then return to the atrium before the hunter catches you. Torch fuel drains over time and oil caches can refill it.

## Run

```sh
make run
```

## Validate

```sh
make test
lua tools/validate_levels.lua 1000 1 all
```

## Controls

- `WASD`: move and strafe
- `Mouse`, `Left/Right`, `Q/E`: turn
- `Shift`: sprint
- Ladder shafts mark shortcut areas
- `M`: toggle minimap
- `N`: generate a new structure
- `R`: replay current seed
- `F2`: enter/replay a seed
- `X`: toggle post-process shader
- `Esc`: toggle mouse capture
