---
name: kumeyuri-render
description: Render Mermaid fenced code blocks inline with kumeyuri when the user wants Claude Code output to include rendered diagrams.
argument-hint: "[markdown-file] [--format text|svg]"
allowed-tools: Read Bash
---

# Kumeyuri Render

Use this skill when a response, Markdown file, issue body, PR description, or doc contains Mermaid fenced code blocks and the user wants rendered diagrams inline.

## Workflow

1. Prefer text output for terminal/chat readability.
2. If a Markdown file path is provided, run the bundled script against that file.
3. If the Mermaid blocks only exist in the conversation, write the Markdown text to a temporary file or pipe it to the script over stdin.
4. Return the transformed Markdown, preserving the original Mermaid fences unless the user asked to replace them.

## Command

```sh
node "${CLAUDE_SKILL_DIR}/scripts/render-mermaid-blocks.mjs" --format text path/to/file.md
```

Use `KUMEYURI_BIN=/path/to/kumeyuri` if `kumeyuri` is not on `PATH`.

Useful flags:

- `--format text` renders terminal-friendly text blocks.
- `--format svg` renders SVG fences.
- `--replace` replaces Mermaid fences instead of appending rendered output below them.
- `--kumeyuri /path/to/kumeyuri` overrides the binary path for one run.

## Output Policy

- Keep rendered output adjacent to its Mermaid source.
- Use fenced `text` blocks for terminal output and fenced `svg` blocks for SVG output.
- If rendering fails, report the failing block number and the command stderr.
- Do not invent a diagram render without running kumeyuri.
