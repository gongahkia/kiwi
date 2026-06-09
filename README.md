# Tikrit

A compact Love2D prototype: a Doom-style raycast survival game where a single pathfinding enemy hunts the player through a freshly generated multi-level megastructure.

Every run generates a new connected structure with large halls, annexes, columns, height changes, and stair corridors. The renderer stays in the old-school 2.5D style: rays draw wall columns plus visible floor and ceiling height transitions.

## Run

```sh
love .
```

## Controls

- `WASD`: move and strafe
- `Mouse`, `Left/Right`, `Q/E`: turn
- `Shift`: sprint
- `M`: toggle minimap
- `N` or `R`: generate a new structure
- `Esc`: toggle mouse capture
