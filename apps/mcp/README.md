# @wat/mcp

stdio MCP server for wat lookup.

Build before using the local config:

```sh
pnpm --filter @wat/mcp build
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
