# MCP Configuration

wat MCP proxies to the wat web API over stdio or Streamable HTTP. It no longer reads seed fixtures or accepts an `api_key` tool argument.

## Modes

| Mode | URL | Transport | Status |
| --- | --- | --- | --- |
| Local stdio | `WAT_API_BASE_URL` | stdio | Works after `pnpm --filter @wat/mcp build`; requires a DB-backed team API key. |
| Hosted remote MCP | `https://wat.example.com/mcp` | Streamable HTTP | Runtime exists; hosted deployment and user/OAuth auth are not complete. |
| Self-host remote MCP | operator URL | Streamable HTTP | Works with `node dist/index.js --http` behind TLS/proxy auth. |

## Local Stdio

Create a team API key from `/team/admin/api-keys`, then build the MCP package:

```sh
pnpm --filter @wat/mcp build
```

Claude Desktop:

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

Cursor `.cursor/mcp.json` or `~/.cursor/mcp.json` uses the same shape:

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

Tool calls do not include credentials:

```json
{
  "term": "CAP",
  "context": "Kubernetes incident notes",
  "limit": 5
}
```

## Tools

| Tool | Purpose | Web API path |
| --- | --- | --- |
| `lookup(term, context?, limit?, min_confidence?)` | Search public plus the authorized team layer. | `GET /api/v1/search` |
| `list_team_acronyms(domain?, cursor?, limit?)` | Page team entries visible to the key. | `GET /api/v1/team/entries` |
| `list_alternatives(term)` | Resolve peer terms/contemporaries. | `GET /api/v1/alternatives` |
| `suggest_definition(term, expansion, meaning, source_url, source_title, domains?)` | Queue a DB-backed suggestion for admin review. | `POST /api/v1/suggestions` |

## Remote Streamable HTTP

Run the MCP package as an HTTP process:

```sh
WAT_API_BASE_URL=https://wat.example.com \
WAT_API_KEY=wat_team_key \
WAT_MCP_HTTP_TOKEN=remote_mcp_token \
WAT_MCP_HOST=0.0.0.0 \
WAT_MCP_PORT=8787 \
node apps/mcp/dist/index.js --http
```

`WAT_MCP_HOST` defaults to `127.0.0.1`. Binding to `0.0.0.0` or another non-loopback host fails unless `WAT_MCP_HTTP_TOKEN` is set. The endpoint validates browser `Origin` headers; set `WAT_MCP_ALLOWED_ORIGINS=https://client.example` when a browser-based client needs CORS.

For clients that support Streamable HTTP MCP with static headers:

```json
{
  "mcpServers": {
    "wat": {
      "type": "http",
      "url": "https://wat.example.com/mcp",
      "headers": {
        "Authorization": "Bearer remote_mcp_token"
      }
    }
  }
}
```

## Key Scopes

Team API keys are DB-backed, hashed at rest, revocable, and scoped to one team.

| Scope     | MCP use                                                     |
| --------- | ----------------------------------------------------------- |
| `search`  | `lookup`, `list_team_acronyms`, `list_alternatives`         |
| `suggest` | `suggest_definition`                                        |
| `write`   | Reserved for future mutation tools.                         |
| `admin`   | Reserved for future admin tools and lifecycle mapping APIs. |

The web API derives `team_id` from the key and rejects a mismatched `X-Wat-Team-Id` when that header is supplied.

## Privacy

The MCP process forwards lookup and suggestion fields to `WAT_API_BASE_URL` with `Authorization: Bearer <WAT_API_KEY>`. It does not persist lookup text, suggestions, API responses, or local fixture files.
