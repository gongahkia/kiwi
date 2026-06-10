# Tikrit

A compact Love2D prototype: a Doom-style raycast survival game where a pathfinding enemy hunts the player through a freshly generated multi-level megastructure.

Every run generates a new connected structure with large halls, themed zones, annexes, columns, height changes, stair corridors, and ladder shafts. The renderer stays in the old-school 2.5D style: rays draw wall columns plus visible floor and ceiling height transitions.

Traversal is the focus: terrain can be rubble, water, moss, grates, catwalks, glass, slag, stairs, or ladders. Different surfaces change movement speed and noise, ladders create steep vertical shortcuts, and sealed shortcuts open once all relays are online.

Survive, activate every relay, then return to the atrium before the hunter catches you. Torch fuel drains over time and oil caches can refill it.

## Run

```sh
love .
```

## Controls

- `WASD`: move and strafe
- `Mouse`, `Left/Right`, `Q/E`: turn
- `Shift`: sprint
- Move into ladders to climb
- `M`: toggle minimap
- `N`: generate a new structure
- `R`: replay current seed
- `S`: enter/replay a seed
- `X`: toggle post-process shader
- `Esc`: toggle mouse capture
