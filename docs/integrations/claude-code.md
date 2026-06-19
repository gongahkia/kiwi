# Claude Code

`editors/claude-code/kumeyuri-render` adds `/kumeyuri-render` for rendering
Mermaid fences inline with kumeyuri.

Run from the repository root:

```sh
claude --plugin-dir ./editors/claude-code/kumeyuri-render
```

Validate the plugin:

```sh
claude plugin validate editors/claude-code/kumeyuri-render
```

Set `KUMEYURI_BIN` if the `kumeyuri` binary is not on `PATH`.
