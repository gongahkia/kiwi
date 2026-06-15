# ADR 0001: AST Shape

## Status

Accepted.

## Context

kumeyuri needs one parser output that can drive layout, animation, text, TUI,
SVG, raster, and WASM renderers. Mermaid upstream currently parses the initial
target diagrams through Jison grammars and mutable diagram DBs:

* `flowchart`: `packages/mermaid/src/diagrams/flowchart/parser/flow.jison`
* `sequenceDiagram`: `packages/mermaid/src/diagrams/sequence/parser/sequenceDiagram.jison`
* `stateDiagram` / `stateDiagram-v2`: `packages/mermaid/src/diagrams/state/parser/stateDiagram.jison`

Source inspected: `mermaid-js/mermaid` commit
`be49880fbc2204fc6f4268c1f5cec791f8adc11b`.

Upstream shape notes:

* Flowchart parsing is side-effect oriented. Grammar actions call `yy.addVertex`,
  `yy.addLink`, `yy.addSubGraph`, `yy.addClass`, `yy.setClass`, and style/link
  mutation APIs. `FlowDB.getData()` later normalizes vertices, edges, subgraphs,
  labels, classes, edge IDs, arrows, and direction for rendering.
* Sequence parsing returns an ordered event stream that `SequenceDB.apply`
  interprets into actors, boxes, messages, activations, notes, autonumber events,
  links, properties, details, create/destroy markers, and control blocks.
* State parsing first creates statement trees (`state`, `relation`, `classDef`,
  `style`, `applyClass`, `click`, `dir`), then `StateDB.extract` converts nested
  documents into states, relations, classes, notes, links, and render data.

The upstream data is renderer-shaped and mutation-heavy. kumeyuri needs a
semantic AST that preserves Mermaid intent before layout or renderer-specific
normalization.

## Decision

Use a typed semantic AST with one root enum and diagram-specific payloads:

```text
Diagram
  metadata: DiagramMetadata
  directives: Vec<Directive>
  kind: DiagramKind

DiagramKind
  Flowchart(FlowchartAst)
  Sequence(SequenceAst)
  State(StateAst)
```

Common node/value types:

```text
DiagramMetadata
  title: Option<String>
  accessibility_title: Option<String>
  accessibility_description: Option<String>
  source_span: Span

Directive
  raw: String
  parsed: Option<DirectiveValue>
  source_span: Span

Label
  text: String
  kind: Plain | String | Markdown
  source_span: Span

StyleRef
  class_names: Vec<String>
  inline_styles: Vec<String>
```

Flowchart AST:

```text
FlowchartAst
  direction: Direction
  statements: Vec<FlowStatement>
  nodes: IndexMap<NodeId, FlowNode>
  edges: Vec<FlowEdge>
  subgraphs: Vec<Subgraph>
  classes: IndexMap<ClassId, ClassDef>

FlowStatement
  Node(NodeId)
  Edge(EdgeId)
  Subgraph(SubgraphId)
  ClassDef(ClassId)
  ClassApply { node_ids, class_id }
  LinkStyle { selector, styles }
  Click { node_id, action }

FlowNode
  id: NodeId
  label: Option<Label>
  shape: FlowShape
  metadata: NodeMetadata
  styles: StyleRef

FlowEdge
  id: EdgeId
  from: NodeId
  to: NodeId
  stroke: Normal | Thick | Dotted | Invisible
  arrow_start: ArrowHead
  arrow_end: ArrowHead
  min_length: u16
  label: Option<Label>
  animation_hint: Option<EdgeAnimationHint>
```

Sequence AST:

```text
SequenceAst
  statements: Vec<SequenceStatement>
  participants: IndexMap<ParticipantId, Participant>
  boxes: Vec<ParticipantBox>

SequenceStatement
  Participant(ParticipantId)
  Create(ParticipantId)
  Destroy(ParticipantId)
  Message(Message)
  ActivationStart(ParticipantId)
  ActivationEnd(ParticipantId)
  Note(Note)
  Loop(ControlBlock)
  Alt(ControlBlock)
  Opt(ControlBlock)
  Par(ControlBlock)
  Critical(ControlBlock)
  Break(ControlBlock)
  AutoNumber(AutoNumber)
```

State AST:

```text
StateAst
  direction: Direction
  statements: Vec<StateStatement>
  states: IndexMap<StateId, StateNode>
  transitions: Vec<StateTransition>
  classes: IndexMap<ClassId, ClassDef>

StateStatement
  State(StateId)
  Transition(TransitionId)
  Composite(StateId)
  ClassDef(ClassId)
  ClassApply { state_ids, class_id }
  Style { state_ids, styles }
  Click { state_id, url, tooltip }
  Direction(Direction)

StateNode
  id: StateId
  label: Option<Label>
  kind: Default | Start | End | Fork | Join | Choice | Divider
  descriptions: Vec<String>
  note: Option<StateNote>
  children: Vec<StateStatement>
  styles: StyleRef
```

All AST nodes that originate from source text carry `Span`. Parser recovery
keeps unknown directives and recoverable unsupported syntax as explicit
diagnostics instead of silently dropping them.

## Consequences

* Layout and animation operate on semantic nodes and edges instead of Mermaid's
  renderer DB objects.
* Renderer-specific lowering happens after AST construction: AST -> layout graph
  -> frame stream -> backend output.
* Flowchart group syntax (`A & B --> C & D`) expands to concrete edges but keeps
  a source statement for diagnostics and future formatting.
* Sequence diagrams preserve statement order because animation playback depends
  on temporal order.
* State diagrams preserve nested composite-state documents instead of flattening
  them immediately.
* Upstream parity tests must compare parsed semantics and rendered output; exact
  Mermaid DB object parity is not a goal.

## Rejected

* Reusing Mermaid DB object shapes directly: too coupled to SVG rendering and
  mutation order.
* A single generic graph AST for all diagram types: loses sequence timing and
  state composite semantics.
* Renderer-first AST: blocks the north-star invariant that every renderer
  consumes the same frame stream.
