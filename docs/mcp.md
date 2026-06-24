# MCP Configuration

wat MCP is currently a local stdio server backed by seed/dev fixtures. Hosted/API-backed lookup, DB-backed suggestions, npm publishing, and catalog listings are separate backlog items.

## Modes

| Mode | URL | Transport | Status |
| --- | --- | --- | --- |
| Local clone | none | stdio | Works today after `pnpm --filter @wat/mcp build`. |
| Hosted wat | `https://wat.example.com/mcp` | remote HTTP MCP | Target config shape; no hosted endpoint is live in this repo yet. |
| Self-host | `https://wat.internal.example.com/mcp` or `http://localhost:3000/mcp` | remote HTTP MCP | Target config shape for an operator-hosted MCP endpoint. |

## Local Stdio

Build before connecting local clients:

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
        "WAT_API_KEY": "wat_team_key",
        "WAT_TEAM_ID": "team_123",
        "WAT_TEAM_DOMAINS": "example.com,docs.example.com",
        "WAT_SEED_PATH": "/absolute/path/to/wat/packages/ingest/seeds/manual.json"
      }
    }
  }
}
```

Cursor `.cursor/mcp.json` or `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "wat": {
      "command": "node",
      "args": ["/absolute/path/to/wat/apps/mcp/dist/index.js"],
      "env": {
        "WAT_API_KEY": "wat_team_key",
        "WAT_TEAM_ID": "team_123",
        "WAT_TEAM_DOMAINS": "example.com,docs.example.com",
        "WAT_SEED_PATH": "/absolute/path/to/wat/packages/ingest/seeds/manual.json"
      }
    }
  }
}
```

Every tool call must pass the same value as `api_key`.

```json
{
  "api_key": "wat_team_key",
  "term": "CAP",
  "context": "Kubernetes incident notes",
  "limit": 5
}
```

## Hosted Target

Use this shape once a hosted remote MCP endpoint exists:

Claude Code or any client accepting HTTP MCP config:

```json
{
  "mcpServers": {
    "wat": {
      "type": "http",
      "url": "https://wat.example.com/mcp",
      "headers": {
        "Authorization": "Bearer wat_live_read_key",
        "X-Wat-Team-Id": "team_123"
      }
    }
  }
}
```

Cursor remote MCP:

```json
{
  "mcpServers": {
    "wat": {
      "url": "https://wat.example.com/mcp",
      "headers": {
        "Authorization": "Bearer wat_live_read_key",
        "X-Wat-Team-Id": "team_123"
      }
    }
  }
}
```

Claude Desktop custom connector:

```text
Name: wat
Remote MCP URL: https://wat.example.com/mcp
Auth: OAuth grant issued for team_123 with read or suggestion-write scope
```

## Self-Host Target

Use the same hosted shape with your operator-owned URL:

```json
{
  "mcpServers": {
    "wat": {
      "type": "http",
      "url": "https://wat.internal.example.com/mcp",
      "headers": {
        "Authorization": "Bearer self_host_team_key",
        "X-Wat-Team-Id": "team_123"
      }
    }
  }
}
```

For current local self-host/dev usage, keep using stdio and set:

```sh
WAT_API_KEY=self_host_team_key
WAT_TEAM_ID=team_123
WAT_TEAM_DOMAINS=example.com,docs.example.com
WAT_MCP_ALLOW_WRITE=false
```

## Key Scopes

Expected hosted keys are DB-backed, hashed at rest, and scoped to one team.

| Scope              | MCP use                                                 |
| ------------------ | ------------------------------------------------------- |
| `read`             | `lookup`, `list_team_acronyms`, `list_alternatives`     |
| `suggestion-write` | `suggest_definition`                                    |
| `team-entry-write` | Reserved for future team-entry mutation tools.          |
| `admin`            | Reserved for future admin tools; not needed for lookup. |

Current stdio self-host/dev auth is simpler: `api_key` must match `WAT_API_KEY`. `suggest_definition` also requires `WAT_MCP_ALLOW_WRITE=true` and `WAT_MCP_SUGGESTIONS_PATH`.

## Team ID Behavior

- `WAT_TEAM_ID` labels structured MCP responses and file-backed suggestions.
- `WAT_TEAM_ID` does not grant access by itself; the key still has to match the configured `WAT_API_KEY`.
- `WAT_TEAM_DOMAINS` is a comma-separated allowlist for `list_team_acronyms(domain)`.
- Hosted mode should derive team identity from the authenticated key and reject mismatched `X-Wat-Team-Id`.
