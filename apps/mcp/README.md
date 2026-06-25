# @wat/mcp

stdio MCP server for wat lookup. It calls the wat web API with a team API key generated from the web admin API-key page. See [MCP Configuration](../../docs/mcp.md).

Build before using the local config:

```sh
pnpm --filter @wat/mcp build
```

After publishing, users can run it with npm without cloning the repo:

```sh
npx @wat/mcp@latest
```

## Claude Desktop local stdio

```json
{
  "mcpServers": {
    "wat": {
      "command": "node",
      "args": ["/absolute/path/to/wat/apps/mcp/dist/index.js"],
      "env": {
        "WAT_API_BASE_URL": "https://wat.example.com",
        "WAT_API_KEY": "wat_team_key"
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
        "WAT_API_BASE_URL": "https://wat.example.com",
        "WAT_API_KEY": "wat_team_key"
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
        "WAT_API_BASE_URL": "https://wat.example.com",
        "WAT_API_KEY": "wat_team_key"
      }
    }
  }
}
```

Tools:

- `lookup(term, context?, limit?, min_confidence?)`: returns top matches with citations.
- `list_team_acronyms(domain?, cursor?, limit?)`: returns paged team entries scoped to the API key.
- `list_alternatives(term)`: returns resolved peer alternatives for a matched term.
- `suggest_definition(term, expansion, meaning, source_url, source_title, domains?)`: queues a pending team suggestion through `/api/v1/suggestions`.

## Privacy Notes

MCP calls send term, optional context/domain/cursor/limit/confidence fields, and suggestion fields to the local wat MCP process. The process forwards requests to `WAT_API_BASE_URL` with `Authorization: Bearer <WAT_API_KEY>`. Team identity is derived by the web API from the DB-backed key; the MCP process does not store lookup text or suggestions locally.
