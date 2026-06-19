# kumeyuri MCP

kumeyuri exposes a local MCP server over stdio:

```sh
kumeyuri mcp --transport stdio
```

Do not write logs to stdout when wrapping this command. MCP stdio uses stdout
for JSON-RPC frames.

## Tools

| Tool | Purpose |
| --- | --- |
| `render_diagram` | Render Mermaid source as text, SVG, GIF, APNG, WebP, or VTT. Binary formats return base64 content. |
| `play_diagram` | Spawn `kumeyuri play <file>` as a TUI subprocess and return the process id plus command. |
| `lint_diagram` | Return kumeyuri layout diagnostics for Mermaid source. |
| `list_themes` | Return project, XDG, and bundled kumeyuri themes. |
| `list_diagram_types` | Return Mermaid roots plus kumeyuri support level and caveat text. |

## Claude Code

```sh
claude mcp add --transport stdio kumeyuri -- kumeyuri mcp --transport stdio
```

Use `--scope user` if the server should be available outside the current
project.

## Cursor

Project scope: `.cursor/mcp.json`

```json
{
  "mcpServers": {
    "kumeyuri": {
      "command": "kumeyuri",
      "args": ["mcp", "--transport", "stdio"]
    }
  }
}
```

## Continue

Add the server to the Continue config used by agent mode:

```yaml
mcpServers:
  - name: kumeyuri
    command: kumeyuri
    args:
      - mcp
      - --transport
      - stdio
```

## opencode

`opencode mcp add` can register a local server interactively. Manual config:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "kumeyuri": {
      "type": "local",
      "command": ["kumeyuri", "mcp", "--transport", "stdio"]
    }
  }
}
```

## Goose

Goose stores MCP extensions in YAML config:

```yaml
extensions:
  kumeyuri:
    type: stdio
    name: kumeyuri
    cmd: kumeyuri
    args:
      - mcp
      - --transport
      - stdio
    enabled: true
    timeout: 300
```

## Security

- Treat `render_diagram` and `lint_diagram` input as untrusted Mermaid text;
  kumeyuri still enforces parser and renderer limits.
- `play_diagram` starts a local process. Only pass file paths the user intended
  to open in the TUI.
- HTTP/SSE bearer-token transport is not implemented yet; use stdio for local
  clients until that TODO is complete.
