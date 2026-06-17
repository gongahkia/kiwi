# Mermaid coverage

Last checked: 2026-06-17 against the official Mermaid docs sidebar for Mermaid
11.15.0.

Sources:

- Mermaid syntax list: https://mermaid.js.org/intro/syntax-reference.html
- Flowchart syntax details: https://mermaid.js.org/syntax/flowchart.html
- Pie syntax details: https://mermaid.js.org/syntax/pie.html
- Quadrant Chart syntax details: https://mermaid.js.org/syntax/quadrantChart.html
- ZenUML syntax details: https://mermaid.ai/open-source/syntax/zenuml.html
- Sankey syntax details: https://mermaid.js.org/syntax/sankey.html
- XY Chart syntax details: https://mermaid.js.org/syntax/xyChart.html
- User Journey syntax details: https://mermaid.js.org/syntax/userJourney.html
- GitGraph syntax details: https://mermaid.js.org/syntax/gitgraph.html
- Timeline syntax details: https://mermaid.js.org/syntax/timeline.html
- C4 syntax details: https://mermaid.js.org/syntax/c4.html

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

## Renderer parity notes

Parser support means the grammar is accepted and represented in the AST. It does
not imply Mermaid visual parity. Current text/SVG/raster renderers normalize
several parsed semantics:

- Flowchart classic shapes render with text-glyph border variants. Mermaid v11
  named shapes still render as generic boxes. `classDef`/`class` and edge
  stroke variants are parsed but do not currently change frame styling or line
  glyphs.
- Requirement diagrams use native requirement boxes and relationship glyphs.
  C4 diagrams use row-grouped native boundaries/elements with visible style
  update rows and selected layout calls, not the class-layout fallback.
- Mindmap shapes have lightweight text-glyph decoration only. Classes and icon
  registration are not Mermaid-style rendering.
- Other supported roots are schematic text-frame renderings unless the row
  explicitly calls out a Mermaid-specific visual feature.

## Matrix

| Mermaid diagram type | kumeyuri status | Parser | Layout | Static-render | Animation | Config | Accessibility | Snapshot count | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- |
| Flowchart | Partial | `graph`/`flowchart`; directions `TB`/`TD`/`BT`/`LR`/`RL`; nodes, labels, classic shapes, Mermaid v11 named shapes, normal/thick/dotted/invisible edges, arrow/circle/cross heads, bidirectional links, chains, fan-in/fan-out, subgraphs, nested subgraphs, subgraph direction, `classDef`, `class`, comments, directives. | Layered flow layout with direction transforms and subgraph boxes. | Yes; text-glyph variants for classic node shapes and generic boxes for Mermaid v11 named shapes. | Trace. | Common kumeyuri options only; Mermaid flowchart frontmatter/init config for layout/look/theme/themeVariables/curve/ELK is rejected. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 28 | Named shapes, classes, and edge stroke variants are semantic-only in rendered frames today. |
| Sequence Diagram | Partial | `sequenceDiagram`; participants, actors, aliases, create/destroy, messages, self messages, solid/dotted/open/cross/bidirectional arrows, `+`/`-` activation shorthand, activate/deactivate, notes left/right/over, `loop`/`alt`/`opt`/`par`/`critical`/`break`/`rect`, boxes, `autonumber`, comments, directives. | Lane-based timeline with text approximations for activation bars, participant boxes, destroy markers, autonumber labels, and control regions. | Yes. | Playback. | Common kumeyuri options only; Mermaid sequence config/styling is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 19 | Mermaid `rect` colors, activation styling, box colors, create markers, and participant styling are generic. |
| Class Diagram | Partial | `classDiagram`; class declarations, class blocks, members, visibility markers, methods/fields, annotations, direction, solid/dotted relationships, inheritance/aggregation/composition/cardinality markers, labels, comments, directives. | Class relationship layout. | Yes; quoted relationship cardinalities render near edge endpoints. | Trace. | Common kumeyuri options only; Mermaid class styling/click/config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 5 | Relationship marker rendering is approximate. |
| State Diagram | Partial | `stateDiagram`/`stateDiagram-v2`; direction, states, aliases, descriptions, transitions with labels, start/end, fork/join, choice, divider, composite states, notes left/right, classes, comments, directives. | Flow layout with composite-state recursion. | Yes. | Transitions. | Common kumeyuri options only; Mermaid state layout/look config is rejected. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 10 | Some Mermaid state-specific shapes/styles are approximate. |
| Entity Relationship Diagram | Partial | `erDiagram`; entities, attributes, keys, identifying/non-identifying relationships, cardinalities, labels, comments, directives. | ER relationship layout. | Yes. | Trace. | Common kumeyuri options only; Mermaid ER styling/config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 3 | No full Mermaid ER style parity. |
| User Journey | Partial | `journey`; title, ordered sections, tasks, scores validated to `1..=5`, actors, comments, directives. | Section/task layout with stable actor style ordering. | Yes; actor color parity is approximated with deterministic text swatches. | Trace. | Common kumeyuri options only; Mermaid journey theme/config directives are accepted but not interpreted as colors. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 4 | Mermaid journey actor color palettes and section fills map to glyph swatches, not terminal color styling. |
| Gantt | Partial | `gantt`; title, `dateFormat`, `axisFormat`, sections, task tags (`active`, `done`, `crit`, `milestone`), ids, metadata, config-like statements (`excludes`, `weekend`, `tickInterval`, `todayMarker`, `weekday`, `click`). | Date-aware day scale with duration/dependency scheduling and basic exclusion handling. | Yes; axis labels honor common `axisFormat` tokens and `tickInterval` day/week/month values. | Trace. | Parses selected Gantt config-like statements; `click` remains semantic-only. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 4 | Calendar semantics are day-level and do not cover time-of-day scales. |
| Pie Chart | Partial | `pie`; `showData`, inline/header title, ordered slices with positive numeric values, comments, directives. | Pie/legend layout with slice percent labels and selected legend placement. | Yes; `showData` renders legend values in brackets. | Trace. | Interprets Mermaid pie `textPosition` and `legendPosition` from init/config directives; theme fields are accepted but renderer theme variables are not mapped. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 4 | `donutHole`, `highlightSlice`, hover behavior, and Mermaid `themeVariables` colors are not rendered. |
| Quadrant Chart | Static-only | `quadrantChart`; title, `x-axis`, `y-axis`, `quadrant-1` through `quadrant-4`, point coordinates `[x, y]` validated to `0..=1`, classes, comments, directives. | Fixed quadrant plot with centered cross-axis, axis labels, quadrant labels, and point labels. | Yes. | Static frame. | Common kumeyuri options only; Mermaid quadrant theme/config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 2 | Classes are semantic-only; Mermaid quadrant CSS/theme rendering is not mapped. |
| Requirement Diagram | Static-only | `requirementDiagram`; requirement kinds, fields (`id`, `text`, `risk`, `verifyMethod`), elements, relationships (`contains`, `copies`, `derives`, `satisfies`, `verifies`, `refines`, `traces`), direction, styles, classes, comments, directives; invalid risk/verify/field/relationship fixtures. | Requirement-specific box layout with Requirement/Element rows. | Yes; `contains` renders a source `⊕` marker, other relationships render dashed lines with arrowheads and `<<type>>` labels. | Static frame. | Common kumeyuri options only; Mermaid requirement config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 3 | Styles/classes are semantic-only; terminal styling does not map Mermaid CSS colors yet. |
| GitGraph Diagram | Partial | `gitGraph` with optional `LR`/`TB`/`BT`; `commit`, `branch`, `checkout`/`switch`, `merge`, `cherry-pick`, ids, tags, commit type, branch order, comments, directives. | Commit graph layout with branch order lanes. | Yes. | Trace. | Mermaid gitgraph theme/config directives are accepted but not interpreted; common kumeyuri options apply. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 4 | Config fields like `showBranches`, `mainBranchOrder`, and label rotation are semantic-only in fixtures. |
| C4 Diagram | Static-only | `C4Context`, `C4Container`, `C4Component`, `C4Dynamic`, `C4Deployment`; title, people/systems/containers/components/db/queue variants, external variants, boundaries, deployment nodes, relationship direction aliases, indexed/bidirectional indexed relationships, style/layout calls. | C4-specific row layout with nested boundaries, deployment nodes, and relationship routing. | Yes; renders people/systems/containers/components/db/queue variants, boundary frames, relationship labels, and style update rows. | Static frame. | Supports `LAYOUT_TOP_DOWN`, `LAYOUT_LEFT_RIGHT`, and `UpdateLayoutConfig` row limits; legend/layout calls are semantic-only, extra tag/sprite/link args are ignored, and unsupported tag/sprite/shape macros are rejected. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 3 | C4 geometry is text-frame approximate; CSS colors are shown as style rows rather than terminal color mapping. |
| Mindmaps | Partial | `mindmap`; indentation tree, labels, all documented shapes, icon fallback tokens, inline/standalone classes, comments, directives, single-line Markdown labels. | Tree layout with unclear-indentation parent fallback and deep-tree coverage. | Yes; limited shape glyph decoration and icon text fallback. | Trace. | Common kumeyuri options only; Mermaid icon registration/config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 4 | Classes are semantic-only; multi-line Markdown labels and full Mermaid CSS styling are not rendered. |
| Timeline | Partial | `timeline`; title, ordered sections, periods with multiple events, continuation events, empty section statements, comments, directives. | Timeline reveal layout. | Yes; empty sections without periods are parser-only and do not render visible section bands. | Trace. | Mermaid timeline theme/config directives are accepted but not interpreted; common kumeyuri options apply. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 4 | Mermaid `timeline TD` direction and color/theme variables are not rendered. |
| ZenUML | Static-only | `zenuml`; title, annotator and alias participants, async arrows, call syntax, `new`, `return`, `if`/`else`/`while`/`for`/`opt`/`par`/`try`/`catch`/`finally` fragments, `//` comments, directives. | Sequence-style lanes with participant boxes, lifelines, messages, creates, returns, and fragment labels. | Yes. | Static frame. | Common kumeyuri options only; ZenUML theme/config is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 2 | Static renderer is schematic and does not model ZenUML activation stack styling or rich return positioning. |
| Sankey | Static-only | `sankey`/`sankey-beta`; CSV rows as `source,target,value`, quoted source/target fields, positive numeric values, comments, directives. | Layered flow layout with node boxes and routed links. | Yes; link labels show raw values. | Static frame. | Common kumeyuri options only; Mermaid Sankey config/color behavior is not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 2 | Link widths/colors are not proportional to values; renderer is schematic text-flow. |
| XY Chart | Static-only | `xychart`/`xychart-beta`; optional orientation token, title, x/y axis titles, category/range axes, `bar` and `line` numeric series, comments, directives. | Fixed plot layout with axis labels, bars, and line points. | Yes. | Static frame. | Common kumeyuri options only; Mermaid chart config, chart dimensions, and orientation-specific layout are not interpreted. | SVG role/title/desc/text fallback via renderer defaults; Mermaid `accTitle`/`accDescr` is not parsed. | 2 | `horizontal` is parsed but currently rendered with the same vertical text plot. |
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
