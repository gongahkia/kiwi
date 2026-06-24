# @wat/mcp

stdio MCP server for wat lookup.

Build before using the local config:

```sh
pnpm --filter @wat/mcp build
```

After publishing, users can run it with npm without cloning the repo:

```sh
npx @wat/mcp@latest
```

## Claude Desktop

```json
{
  "mcpServers": {
    "wat": {
      "command": "node",
      "args": ["/absolute/path/to/wat/apps/mcp/dist/index.js"],
      "env": {
        "WAT_API_KEY": "wat_team_key",
        "WAT_TEAM_ID": "team_example",
        "WAT_TEAM_DOMAINS": "example.com",
        "WAT_SEED_PATH": "/absolute/path/to/wat/packages/ingest/seeds/manual.json"
      }
    }
  }
}
```

## Cursor

```json
{
  "mcpServers": {
    "wat": {
      "command": "node",
      "args": ["/absolute/path/to/wat/apps/mcp/dist/index.js"],
      "env": {
        "WAT_API_KEY": "wat_team_key",
        "WAT_TEAM_ID": "team_example",
        "WAT_TEAM_DOMAINS": "example.com",
        "WAT_SEED_PATH": "/absolute/path/to/wat/packages/ingest/seeds/manual.json"
      }
    }
  }
}
```

## VSCode + Continue.dev

```json
{
  "mcpServers": {
    "wat": {
      "command": "node",
      "args": ["/absolute/path/to/wat/apps/mcp/dist/index.js"],
      "env": {
        "WAT_API_KEY": "wat_team_key",
        "WAT_TEAM_ID": "team_example",
        "WAT_TEAM_DOMAINS": "example.com",
        "WAT_SEED_PATH": "/absolute/path/to/wat/packages/ingest/seeds/manual.json"
      }
    }
  }
}
```

Tools:

- `lookup(term, context?, limit?, min_confidence?, api_key)`: returns top matches with citations.
- `list_team_acronyms(domain?, cursor?, limit?, api_key)`: returns paged team entries scoped to the API key.
- `suggest_definition(term, expansion, meaning, source_url, source_title, domains?, api_key)`: queues a pending team suggestion when `WAT_MCP_ALLOW_WRITE=true` and `WAT_MCP_SUGGESTIONS_PATH` is configured.

## Privacy Notes

MCP calls send the tool input to the local wat MCP process: `api_key`, term, optional context/domain/cursor/limit/confidence fields, and suggestion fields for `suggest_definition`. The server does not store lookup text. It reads `WAT_API_KEY`, `WAT_TEAM_ID`, `WAT_TEAM_DOMAINS`, and `WAT_SEED_PATH` from its environment.

When `WAT_MCP_ALLOW_WRITE=true`, `suggest_definition` appends pending suggestion records to `WAT_MCP_SUGGESTIONS_PATH`, including term, expansion, meaning, source URL/title, domains, team ID, status, and creation time.
