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

| Mermaid diagram type | kumeyuri status | Parser | Layout | Static-render | Animation | Config | Accessibility | Snapshot count | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- |
| Flowchart | Partial | `graph`/`flowchart`; directions `TB`/`TD`/`BT`/`LR`/`RL`; nodes, labels, classic shapes, Mermaid v11 named shapes, normal/thick/dotted/invisible edges, arrow/circle/cross heads, bidirectional links, chains, fan-in/fan-out, subgraphs, nested subgraphs, subgraph direction, `classDef`, `class`, comments, directives. | Layered flow layout with direction transforms and subgraph boxes. | Yes; text boxes. | Trace. | Common kumeyuri options only; Mermaid frontmatter/init/theme/layout/look/curve/ELK/click config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 20 | Many Mermaid shape differences are semantic-only today. |
| Sequence Diagram | Partial | `sequenceDiagram`; participants, actors, aliases, messages, self messages, solid/dotted/open/cross/bidirectional arrows, notes left/right/over, `loop`/`alt`/`opt`/`par`, comments, directives. | Lane-based timeline. | Yes. | Playback. | Common kumeyuri options only; Mermaid sequence config/styling is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 15 | `autonumber`, activation/deactivation, `critical`, `break`, boxes, and participant styling are not covered. |
| Class Diagram | Partial | `classDiagram`; class declarations, class blocks, members, visibility markers, methods/fields, annotations, direction, solid/dotted relationships, inheritance/aggregation/composition/cardinality markers, labels, comments, directives. | Class relationship layout. | Yes. | Trace. | Common kumeyuri options only; Mermaid class styling/click/config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 4 | Relationship marker/cardinality rendering is approximate. |
| State Diagram | Partial | `stateDiagram`/`stateDiagram-v2`; direction, states, aliases, descriptions, transitions with labels, start/end, fork/join, choice, divider, composite states, notes left/right, classes, comments, directives. | Flow layout with composite-state recursion. | Yes. | Transitions. | Common kumeyuri options only; Mermaid layout/look config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 10 | Some Mermaid state-specific shapes/styles are approximate. |
| Entity Relationship Diagram | Partial | `erDiagram`; entities, attributes, keys, identifying/non-identifying relationships, cardinalities, labels, comments, directives. | ER relationship layout. | Yes. | Trace. | Common kumeyuri options only; Mermaid ER styling/config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 3 | No full Mermaid ER style parity. |
| User Journey | Partial | `journey`; title, sections, tasks, scores, actors, comments, directives. | Section/task layout. | Yes. | Trace. | Common kumeyuri options only; Mermaid journey theme/config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 3 | Actor color/style parity is not covered. |
| Gantt | Partial | `gantt`; title, `dateFormat`, `axisFormat`, sections, task tags (`active`, `done`, `crit`, `milestone`), ids, metadata, config-like statements (`excludes`, `weekend`, `tickInterval`, `todayMarker`, `weekday`, `click`). | Schematic timeline layout. | Yes. | Trace. | Parses selected Gantt config-like statements but does not implement full Mermaid calendar/config semantics. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 3 | Calendar/date semantics are schematic. |
| Pie Chart | Partial | `pie`; `showData`, inline/header title, slices with numeric values, comments, directives. | Pie/legend layout. | Yes. | Trace. | Common kumeyuri options only; Mermaid pie config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 3 | Percentage/value label parity is incomplete. |
| Quadrant Chart | None | Rejects `quadrantChart`. | No. | No. | No. | No. | No SVG output. | 0 | No parser root. |
| Requirement Diagram | Static-only | `requirementDiagram`; requirement kinds, fields (`id`, `text`, `risk`, `verifyMethod`), elements, relationships (`contains`, `copies`, `derives`, `satisfies`, `verifies`, `refines`, `traces`), direction, styles, classes, comments, directives. | Class-layout surface. | Yes. | Static frame. | Common kumeyuri options only; Mermaid requirement config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 3 | Requirement-specific geometry is not implemented. |
| GitGraph Diagram | Partial | `gitGraph` with optional `LR`/`TB`/`BT`; `commit`, `branch`, `checkout`/`switch`, `merge`, `cherry-pick`, ids, tags, commit type, branch order, comments, directives. | Commit graph layout. | Yes. | Trace. | Common kumeyuri options only; Mermaid gitgraph theme/config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 3 | Branch ordering and merge/cherry-pick options need broader parity fixtures. |
| C4 Diagram | Static-only | `C4Context`, `C4Container`, `C4Component`, `C4Dynamic`, `C4Deployment`; title, people/systems/containers/components/db/queue variants, external variants, boundaries, deployment nodes, relationships, indexed relationships, style/layout calls. | Class-layout surface. | Yes. | Static frame. | Parses style/layout calls but does not render full Mermaid C4 geometry/style semantics. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 3 | C4 boundaries/containers are approximate. |
| Mindmaps | Partial | `mindmap`; indentation tree, labels, selected shapes, icons, classes, comments, directives. | Tree layout. | Yes. | Trace. | Common kumeyuri options only; Mermaid icon registration/config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 3 | Full mindmap styling and icon fallback parity is not covered. |
| Timeline | Partial | `timeline`; title, sections, periods, events, comments, directives. | Timeline reveal layout. | Yes. | Trace. | Common kumeyuri options only; Mermaid timeline config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 3 | Multi-event/long-label parity needs broader fixtures. |
| ZenUML | None | Rejects `zenuml`. | No. | No. | No. | No. | No SVG output. | 0 | No parser root. |
| Sankey | None | Rejects `sankey`. | No. | No. | No. | No. | No SVG output. | 0 | No parser root. |
| XY Chart | None | Rejects `xychart`/`xychart-beta`. | No. | No. | No. | No. | No SVG output. | 0 | No parser root. |
| Block Diagram | None | Rejects `block`. | No. | No. | No. | No. | No SVG output. | 0 | No parser root. |
| Packet | None | Rejects `packet`. | No. | No. | No. | No. | No SVG output. | 0 | No parser root. |
| Kanban | None | Rejects `kanban`. | No. | No. | No. | No. | No SVG output. | 0 | No parser root. |
| Architecture | None | Rejects `architecture-beta`. | No. | No. | No. | No. | No SVG output. | 0 | No parser root. |
| Radar | None | Rejects `radar-beta`. | No. | No. | No. | No. | No SVG output. | 0 | No parser root. |
| Event Modeling | None | Rejects `eventmodeling`. | No. | No. | No. | No. | No SVG output. | 0 | No parser root. |
| Treemap | None | Rejects `treemap-beta`. | No. | No. | No. | No. | No SVG output. | 0 | No parser root. |
| Venn | None | Rejects `venn-beta`. | No. | No. | No. | No. | No SVG output. | 0 | No parser root. |
| Ishikawa | None | Rejects `ishikawa-beta`. | No. | No. | No. | No. | No SVG output. | 0 | No parser root. |
| Wardley | None | Rejects `wardley-beta`. | No. | No. | No. | No. | No SVG output. | 0 | No parser root. |
| TreeView | None | Rejects `treeView-beta`. | No. | No. | No. | No. | No SVG output. | 0 | No parser root. |
