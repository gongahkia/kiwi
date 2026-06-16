# Animation Defaults

This document defines the default animation contract for Phase 2. The core
emits deterministic `Timeline` values made of ordered `KeyFrame`s. Renderers may
add visual effects between frames, but they must not change frame order,
duration, or marker ids.

## Common Contract

- Static rendering is frame 0 for every animated diagram.
- Each keyframe owns a complete `Frame`; renderers do not diff frames in core.
- Durations are stored as `std::time::Duration`.
- Marker ids are stable strings derived from semantic ids where possible.
- `KeyFrameMarkerKind::Enter` marks newly introduced focus.
- `KeyFrameMarkerKind::Active` marks current focus.
- `KeyFrameMarkerKind::Exit` marks focus leaving the current step.
- `KeyFrameMarkerKind::Hold` marks context that should remain visible but muted.
- Default timelines do not loop. Looping is a renderer or directive override.

## Defaults

| Diagram | Default mode | Step source | Frame duration |
| --- | --- | --- | --- |
| `sequenceDiagram` | `playback` | participant declarations, messages, notes, control blocks | 700 ms |
| `flowchart` / `graph` | `trace` | reachable edges from graph roots in breadth-first order | 550 ms |
| `stateDiagram-v2` | `transitions` | state transitions in source order | 650 ms |

## Sequence Playback

Sequence playback presents the diagram as an event stream.

1. Frame 0 shows all participants and lifelines.
2. Participant declarations get `Enter` markers on participant boxes.
3. Each message frame marks the sender and receiver lanes as `Active`.
4. The active message edge gets an `Active` marker.
5. Notes and control blocks get `Enter` on first display, then `Hold`.
6. Self messages keep the participant lane `Active`.

If a sequence diagram has no messages, the timeline is a single static frame.

## Flowchart Trace

Flowchart trace highlights graph reachability without changing layout.

1. Frame 0 shows the full static graph.
2. Roots are nodes with no incoming visible edges. If every node has incoming
   edges, source order chooses the first root.
3. Traversal is breadth-first by default.
4. Node first visit gets `Enter`.
5. Current node and outgoing edge get `Active`.
6. Previously visited nodes get `Hold`.
7. Back edges and self edges get `Active` only when traversed.

Disconnected roots are traced after the current component, preserving source
order.

## State Transitions

State transitions pulse state changes in source order.

1. Frame 0 shows the full static state diagram.
2. Initial states (`[*]`) get `Enter` on first transition.
3. The current source state gets `Exit`.
4. The transition edge gets `Active`.
5. The target state gets `Enter`, then `Active` on the next frame if it is the
   next source.
6. Composite state containers get `Hold` while any child state is active.

If a state diagram has no transitions, the timeline is a single static frame.

## Directive Overrides

Directive parsing will map:

```mermaid
%%{ animate: 'trace', speed: 1.0, loop: false, easing: 'linear' }%%
```

to `AnimationConfig`.

Schema:

- `animate`: one of `playback`, `trace`, `transitions`, `none`.
- `speed`: finite `f32` greater than `0.0`; default `1.0`.
- `loop`: boolean; stored as `AnimationConfig::repeat`; default `false`.
- `easing`: one of `linear`, `ease`; default `linear`.

Absent directive means use the diagram default. An explicit `animate: 'none'`
disables animation. Multiple `animate` directives are applied in source order;
the last valid directive wins. `Animator::animate_diagram` validates the mode
against the diagram kind and applies `speed` by scaling keyframe duration.

## Snapshot Contract

Animation snapshot tests should hash:

- diagram kind;
- animation mode;
- keyframe count;
- each frame duration in milliseconds;
- frame glyph grid;
- marker id, kind, and region.

Snapshots should ignore renderer-only effects such as fades, slides, terminal
palette transitions, and TUI cursor state.
