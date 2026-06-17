# Mermaid coverage

Last checked: 2026-06-17 against the official Mermaid docs sidebar for Mermaid
11.15.0.

Sources:

- Mermaid syntax list: https://mermaid.js.org/intro/syntax-reference.html
- Flowchart syntax details: https://mermaid.js.org/syntax/flowchart.html

Local evidence:

- Diagram roots: `crates/kumeyuri-core/src/ast.rs`
- Parser root dispatch and accepted headers: `crates/kumeyuri-core/src/parser.rs`
- Static render dispatch: `crates/kumeyuri-core/src/frame.rs`
- Animation modes: `crates/kumeyuri-core/src/animator.rs`
- Snapshot inputs: `tests/snapshots/*/input/*.mmd`

## Status key

| Status | Meaning |
| --- | --- |
| Partial | Parser and renderer exist, but this is not full Mermaid parity. |
| Static-only | Parser and renderer exist; animation collapses to a static frame. |
| None | No parser root/`DiagramKind` exists; input is rejected. |

## Common configurability

These apply to all parsed diagrams unless noted:

| Area | Current support |
| --- | --- |
| Output formats | `text`, `svg`, `gif`, `apng`, `webp`, `tui` |
| Themes | `default`, `mono`, `tokyo-night`, `github`, `dracula` |
| Dark theme | SVG only via `--dark-theme` |
| Charset | `ascii` or `unicode` |
| Layout sizing | `--width` for text/SVG/raster/TUI frames |
| SVG/raster surface | `--padding`, `--font` |
| Directives | Only `%%{ animate: ... }%%` is interpreted. Other Mermaid directives are stored and ignored by renderers. |
| Mermaid config parity | No Mermaid frontmatter/init/theme/layout config parity. No JS callbacks, click handlers, or Mermaid security-level behavior. |

## Matrix

| Mermaid diagram type | kumeyuri status | Static render | Animation | Current syntax/config coverage |
| --- | --- | --- | --- | --- |
| Flowchart | Partial | Yes | Trace | `graph`/`flowchart`; directions `TB`/`TD`/`BT`/`LR`/`RL`; nodes, labels, classic shapes, Mermaid v11 named shape syntax is parsed, normal/thick/dotted/invisible edges, arrow/circle/cross heads, bidirectional links, chain/fan-in/fan-out, subgraphs, nested subgraphs, subgraph direction, `classDef`, `class`, comments, directives. Renderer draws flow nodes as text boxes, so many Mermaid shape differences are semantic-only today. |
| Sequence Diagram | Partial | Yes | Playback | `sequenceDiagram`; participants and actors, aliases, messages, self messages, solid/dotted/open/cross/bidirectional arrows, notes left/right/over, `loop`/`alt`/`opt`/`par`, comments, directives. `autonumber`, activation/deactivation, `critical`, `break`, boxes, and Mermaid styling/theme config are not covered. |
| Class Diagram | Partial | Yes | Trace | `classDiagram`; class declarations, class blocks, members, visibility markers, methods/fields, annotations, direction, solid/dotted relationships, inheritance/aggregation/composition/cardinality markers, labels, comments, directives. Advanced Mermaid class styling/click/interactivity is not covered. |
| State Diagram | Partial | Yes | Transitions | `stateDiagram`/`stateDiagram-v2`; direction, states, aliases, descriptions, transitions with labels, start/end, fork/join, choice, divider, composite states, notes left/right, classes, comments, directives. Mermaid layout/look config is not interpreted. |
| Entity Relationship Diagram | Partial | Yes | Trace | `erDiagram`; entities, attributes, keys, identifying/non-identifying relationships, cardinalities, labels, comments, directives. No full Mermaid ER styling/config parity. |
| User Journey | Partial | Yes | Trace | `journey`; title, sections, tasks, scores, actors, comments, directives. Styling/config beyond common kumeyuri options is not covered. |
| Gantt | Partial | Yes | Trace | `gantt`; title, `dateFormat`, `axisFormat`, sections, task tags (`active`, `done`, `crit`, `milestone`), ids, metadata, and config-like statements (`excludes`, `weekend`, `tickInterval`, `todayMarker`, `weekday`, `click`) are parsed. Calendar semantics are rendered schematically, not with full Mermaid date/layout behavior. |
| Pie Chart | Partial | Yes | Trace | `pie`; `showData`, inline/header title, slices with numeric values, comments, directives. Mermaid pie config is not interpreted. |
| Quadrant Chart | None | No | No | No parser root. |
| Requirement Diagram | Static-only | Yes | Static frame | `requirementDiagram`; requirement kinds, requirement fields (`id`, `text`, `risk`, `verifyMethod`), elements, relationships (`contains`, `copies`, `derives`, `satisfies`, `verifies`, `refines`, `traces`), direction, styles, classes, comments, directives. Rendered through the class-layout surface. |
| GitGraph Diagram | Partial | Yes | Trace | `gitGraph` with optional `LR`/`TB`/`BT`; `commit`, `branch`, `checkout`/`switch`, `merge`, `cherry-pick`, ids, tags, commit type, branch order, comments, directives. Full Mermaid gitgraph styling/config is not covered. |
| C4 Diagram | Static-only | Yes | Static frame | `C4Context`, `C4Container`, `C4Component`, `C4Dynamic`, `C4Deployment`; title, people/systems/containers/components/db/queue variants, external variants, boundaries, deployment nodes, relationships, indexed relationships, style/layout calls are parsed. Rendered through the class-layout surface, so C4 geometry/style parity is limited. |
| Mindmaps | Partial | Yes | Trace | `mindmap`; indentation tree, labels, selected shapes, icons, classes, comments, directives. Mermaid icon registration and full mindmap styling are not covered. |
| Timeline | Partial | Yes | Trace | `timeline`; title, sections, periods, events, comments, directives. Mermaid timeline styling/config is not covered. |
| ZenUML | None | No | No | No parser root. |
| Sankey | None | No | No | No parser root. |
| XY Chart | None | No | No | No parser root. |
| Block Diagram | None | No | No | No parser root. |
| Packet | None | No | No | No parser root. |
| Kanban | None | No | No | No parser root. |
| Architecture | None | No | No | No parser root. |
| Radar | None | No | No | No parser root. |
| Event Modeling | None | No | No | No parser root. |
| Treemap | None | No | No | No parser root. |
| Venn | None | No | No | No parser root. |
| Ishikawa | None | No | No | No parser root. |
| Wardley | None | No | No | No parser root. |
| TreeView | None | No | No | No parser root. |

Snapshot input counts for supported roots:

| Root | Count |
| --- | ---: |
| `flowchart` | 20 |
| `sequence` | 15 |
| `state` | 10 |
| `class` | 4 |
| `c4` | 3 |
| `er` | 3 |
| `gantt` | 3 |
| `gitgraph` | 3 |
| `journey` | 3 |
| `mindmap` | 3 |
| `pie` | 3 |
| `requirement` | 3 |
| `timeline` | 3 |
