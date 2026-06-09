# Tikrit

A compact Love2D prototype: a Doom-style raycast survival game where a single pathfinding enemy hunts the player through a freshly generated multi-level megastructure.

Every run generates a new connected structure with large halls, themed zones, annexes, columns, height changes, stair corridors, and ladder shafts. The renderer stays in the old-school 2.5D style: rays draw wall columns plus visible floor and ceiling height transitions.

Traversal is the focus: terrain can be rubble, water, moss, grates, catwalks, glass, slag, stairs, or ladders. Different surfaces change movement speed, ladders create steep vertical shortcuts, and the tracking entity can use the same traversal graph to hunt the player.

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
- `N` or `R`: generate a new structure
- `Esc`: toggle mouse capture
