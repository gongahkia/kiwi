# X launch thread draft

Status: draft only. Scheduling requires account access.

Recommended window:

- Tuesday 09:10 PT: post 1
- Tuesday 09:25 PT: post 2
- Tuesday 09:40 PT: post 3

Fallback window:

- Wednesday 09:10 PT: post 1
- Wednesday 09:25 PT: post 2
- Wednesday 09:40 PT: post 3

## Post 1

Text:

```text
Kumeyuri turns Mermaid into animated diagrams for terminals, SVG, GIF/APNG/WebP, and WASM embeds.

Same .mmd source, one Rust frame stream, multiple renderers.

Repo: https://github.com/gongahkia/kumeyuri
```

Attachment:

```text
demos/rendered/http-request-lifecycle.gif
```

## Post 2

Text:

```text
The wedge: SVG is a backend, not the architecture.

Kumeyuri parses Mermaid into a semantic AST, lays it out once, animates a deterministic frame stream, then renders that stream for terminal playback, docs, READMEs, and browser components.
```

Attachment:

```text
demos/rendered/microservice-fan-out.gif
```

## Post 3

Text:

```text
Current scope is intentionally narrow: flowcharts, sequence diagrams, and state diagrams first.

Tests cover parser fixtures, static snapshots, animation hashes, SVG sanitization, raster snapshots, browser playback, and WASM bundle size.
```

Attachment:

```text
demos/rendered/os-scheduler-state-machine.gif
```
