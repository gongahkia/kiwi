# MCP Configuration

wat MCP is a local stdio server that proxies to the wat web API. It no longer reads seed fixtures or accepts an `api_key` tool argument.

## Modes

| Mode | URL | Transport | Status |
| --- | --- | --- | --- |
| Local stdio | `WAT_API_BASE_URL` | stdio | Works after `pnpm --filter @wat/mcp build`; requires a DB-backed team API key. |
| Hosted remote MCP | `https://wat.example.com/mcp` | remote HTTP MCP | Not implemented in this repo yet. |
| Self-host remote MCP | operator URL | remote HTTP MCP | Same target shape as hosted remote MCP; not implemented in this repo yet. |

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

## Hosted Remote Target

Use this shape only after a remote MCP endpoint is added:

```json
{
  "mcpServers": {
    "wat": {
      "type": "http",
      "url": "https://wat.example.com/mcp",
      "headers": {
        "Authorization": "Bearer wat_live_read_key"
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

The local MCP process forwards lookup and suggestion fields to `WAT_API_BASE_URL` with `Authorization: Bearer <WAT_API_KEY>`. It does not persist lookup text, suggestions, API responses, or local fixture files.
