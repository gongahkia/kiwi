# Smart Layout

Smart layout has two layers:

1. deterministic heuristics in `kumeyuri-core` and `kumeyuri-cli`;
2. an optional AI companion boundary that can be loaded by `kumeyuri layout --ai`.

The deterministic path is always first. AI is opt-in and currently stops at the
dynamic binding boundary.

## Deterministic Heuristics

| Heuristic | Scope | Behavior |
| --- | --- | --- |
| Crossing minimisation | Flowchart layered layout | Runs four forward/backward barycenter sweeps over layered edges and reorders nodes inside each layer to reduce crossings. |
| Long-label wrapping | Flowchart labels | `kumeyuri render --max-label-width <N>` wraps labels at whitespace and chunks long words when needed before node sizing. |
| Disconnected clustering | Flowchart components | Packs disconnected components after initial placement, preserving subgraph bounds. `TD`/`BT` layouts pack components horizontally; `LR`/`RL` layouts pack vertically. |
| Orphan-node warnings | Flowchart lint/render | Emits `flowchart.orphan_node` when a declared node has no edges and suggests adding an edge or removing the node. |
| Direction-swap warnings | Flowchart lint/render | Emits `flowchart.extreme_aspect_ratio` when rendered width or height is at least 4x the other axis and suggests the opposite direction family. |

`render` prints layout warnings to stderr while still writing the requested
artifact. `lint` reports the same warnings without rendering:

```bash
kumeyuri lint diagram.mmd
kumeyuri lint diagram.mmd --json
```

JSON lint output is the handoff format for tools that want structured
diagnostics. It contains the source file, `ok`, and warning entries with `code`,
`message`, and `suggestion`.

## AI Fallback Boundary

`kumeyuri layout --ai <FILE>` parses the diagram, loads a dynamic library from
`KUMEYURI_AI_DYLIB`, and checks the exported `kumeyuri_ai_abi_version` symbol.
ABI `1` is the only accepted version.

```bash
KUMEYURI_AI_DYLIB=/path/to/libkumeyuri_ai.dylib kumeyuri layout --ai diagram.mmd
```

Current CLI behavior:

- validates the Mermaid source before loading the companion;
- fails if `--ai` is omitted;
- fails if `KUMEYURI_AI_DYLIB` is empty or unset;
- fails on missing or incompatible ABI symbols;
- does not apply an AI rewrite to the input file yet.

The companion crate defines the rewrite contract:

- `LayoutRewriteRequest` carries Mermaid source plus diagnostics from
  `kumeyuri lint --json`;
- `LayoutAssistant` returns `LayoutRewrite` with rewritten source and summary;
- provider config covers OpenAI, Anthropic, OpenRouter, and local llama.cpp;
- BYOK envvars are `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, and
  `OPENROUTER_API_KEY`;
- `present_rewrite_diff` emits a line-based original vs `ai-rewrite` diff;
- `validate_rewrite` rejects empty rewritten source or summary.

Provider network calls and applying rewrites are intentionally outside the
current main-CLI path.

## Recommended Workflow

1. Run `kumeyuri lint --json diagram.mmd` and inspect deterministic warnings.
2. Try deterministic edits first: split orphan nodes, change `graph TD`/`LR`, or
   set `--max-label-width`.
3. Use `kumeyuri layout --ai` only when deterministic hints are insufficient and
   a compatible companion dynamic library is available.
4. Review any companion diff before applying it to source.
