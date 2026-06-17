---
name: kumeyuri-render
description: Render Mermaid fenced code blocks inline with kumeyuri in OpenCode responses.
license: MIT
compatibility: opencode
metadata:
  integration: kumeyuri
---

# Kumeyuri Render

Use this when the user wants Mermaid diagrams rendered inline in OpenCode output.

## Preferred Path

If the `kumeyuri_render` tool is available, call it with either raw Mermaid source or Markdown containing Mermaid fenced code blocks.

Use:

- `format: "text"` for terminal/chat output.
- `format: "svg"` only when the user specifically asks for SVG.
- `replace: true` only when the user asks to omit the original Mermaid fence.

## Script Fallback

If the tool is unavailable, run:

```sh
node .opencode/scripts/render-mermaid-blocks.mjs --format text path/to/file.md
```

Set `KUMEYURI_BIN=/path/to/kumeyuri` when `kumeyuri` is not on `PATH`.

## Rules

- Keep rendered output adjacent to its Mermaid source.
- Do not invent render output.
- If rendering fails, report the failing block number and stderr.
