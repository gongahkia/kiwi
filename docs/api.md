# API

Machine-readable REST spec: [`docs/openapi.yml`](openapi.yml).

## REST

Base path: `/api/v1`

### `GET /search`

Lookup public glossary entries. Token requests can include scoped team entries.

Query params:

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `q` | string | yes | Search query. `query` is accepted as an alias. |
| `limit` | number | no | Defaults to `10`. Non-positive or invalid values fall back to `10`. |
| `min_confidence` | `T1` \| `T2` \| `T3` \| `T4` | no | Returns entries at or above the requested confidence threshold. |

Example:

```sh
curl 'http://localhost:3000/api/v1/search?q=CAP&limit=2'
```

API clients can pass a DB-backed team API key with either `Authorization: Bearer $WAT_API_KEY` or `X-API-Key: $WAT_API_KEY`. Create keys in `/team/admin/api-keys`. Token requests can also send `X-Wat-User-Id`; `X-Wat-Team-Id` is optional and must match the key's team when supplied.

Browser/API CORS is deny-by-default. Set comma-separated `WAT_ALLOWED_ORIGINS` for web clients and `WAT_EXTENSION_ORIGINS` for installed extension origins such as `chrome-extension://<id>` or `moz-extension://<id>`.

Every API response includes `X-Request-Id`. Clients may send `X-Request-Id`; otherwise the server generates one and includes the same value in request, search, and error logs.

Error responses use this JSON shape:

```json
{
  "error": "invalid_api_key",
  "code": "invalid_api_key",
  "message": "invalid_api_key",
  "request_id": "req_123"
}
```

Rate-limit settings:

| Env                        | Default | Scope                          |
| -------------------------- | ------- | ------------------------------ |
| `WAT_RATE_LIMIT_WINDOW_MS` | `60000` | fixed window                   |
| `WAT_RATE_LIMIT_IP`        | `60`    | anonymous and token requests   |
| `WAT_RATE_LIMIT_USER`      | `120`   | token requests with user scope |
| `WAT_RATE_LIMIT_TEAM`      | `300`   | token requests with team scope |

Rate-limit response headers:

- `X-RateLimit-Limit`
- `X-RateLimit-Remaining`
- `X-RateLimit-Reset`
- `X-RateLimit-Scope`
- `Retry-After`

Token example:

```sh
curl \
  -H "Authorization: Bearer $WAT_API_KEY" \
  -H "X-Wat-User-Id: user_123" \
  -H "X-Wat-Team-Id: team_123" \
  'http://localhost:3000/api/v1/search?q=CAP&limit=2'
```

Response:

```json
{
  "matches": [
    {
      "entry": {
        "id": "seed-cap-common-alerting-protocol",
        "term": "CAP",
        "term_normalized": "cap",
        "expansions": ["Common Alerting Protocol"],
        "contemporaries": [],
        "domains": ["ops", "alerts"],
        "meaning_short": "A standardized format for exchanging emergency alerts.",
        "sources": [
          {
            "url": "https://en.wikipedia.org/wiki/Common_Alerting_Protocol",
            "title": "Common Alerting Protocol",
            "publisher": "Wikipedia",
            "license": "CC-BY-SA-4.0",
            "retrieved_at": "2026-06-19T00:00:00.000Z",
            "snippet": "Wikipedia describes CAP as an XML-based data format for warnings.",
            "source_quality": "secondary"
          }
        ],
        "confidence_tier": "T2",
        "layer": "public",
        "aliases": []
      },
      "score": 1,
      "score_breakdown": {
        "bm25": 1,
        "contemporary": 0,
        "domain": 0
      }
    }
  ]
}
```

No-match response:

```json
{
  "matches": [],
  "suggest_url": "/suggest?term=unknown"
}
```

### `GET /entries/:id/contemporaries`

Resolve an entry's `contemporaries` names against entries visible to the caller. Missing alternative names are returned as unresolved stubs instead of 404s.

Example:

```sh
curl 'http://localhost:3000/api/v1/entries/seed-csr-client-side-rendering/contemporaries'
```

Response:

```json
[
  {
    "term": "SSR",
    "meaning_short": "Rendering UI markup on the server before sending it to the client.",
    "id": "seed-ssr-server-side-rendering"
  },
  {
    "term": "MPA",
    "meaning_short": null,
    "id": null
  }
]
```

### `POST /custom-entries`

Create a browser/API-saved glossary entry in a personal or team layer. Anonymous requests are rejected.

Auth:

- `Authorization: Bearer $WAT_API_KEY` or `X-API-Key: $WAT_API_KEY` is required.
- `X-Wat-User-Id` is required for writes.
- `X-Wat-Team-Id` is optional for team writes and must match the authenticated key's team when supplied.

Request body:

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `term` | string | yes | Acronym or term to save. Trimmed; empty values are rejected. |
| `expansion` | string | yes | Expansion to save. Trimmed; empty values are rejected. |
| `meaning` | string | no | Defaults to `Custom definition for <term>.` |
| `mode` | `create` \| `upsert` | no | Defaults to `create`. `upsert` updates an existing entry with the same `scope`, `term`, and `expansion`; otherwise it creates one. |
| `scope` | `personal` \| `team` | no | Defaults to `personal`. Team scope writes to the caller's team layer. |
| `domains` | string[] | no | Trimmed, lowercased, deduplicated, capped at 12. |
| `sourceUrl` | string | no | Valid URLs are preserved. Missing or invalid values become `https://wat.local/custom/<id>`. |
| `sourceTitle` | string | no | Defaults to the source hostname or `Browser custom entry`. |

Stored source behavior:

- Personal entries use `proprietary-personal`.
- Team entries use `proprietary-team`.
- `publisher` is `wat browser extension`.
- `retrieved_at` is generated at write time.

Personal example:

```sh
curl \
  -X POST 'http://localhost:3000/api/v1/custom-entries' \
  -H "Authorization: Bearer $WAT_API_KEY" \
  -H "Content-Type: application/json" \
  -H "X-Wat-User-Id: user_123" \
  --data '{
    "mode": "upsert",
    "scope": "personal",
    "term": "CAP",
    "expansion": "Change Approval Process",
    "meaning": "Private release-review shorthand.",
    "domains": ["deploys", "ops"],
    "sourceUrl": "https://docs.example.test/releases/cap",
    "sourceTitle": "Release process"
  }'
```

Team example:

```sh
curl \
  -X POST 'http://localhost:3000/api/v1/custom-entries' \
  -H "Authorization: Bearer $WAT_API_KEY" \
  -H "Content-Type: application/json" \
  -H "X-Wat-User-Id: user_123" \
  -H "X-Wat-Team-Id: team_123" \
  --data '{
    "scope": "team",
    "term": "RTO",
    "expansion": "Recovery Time Objective",
    "domains": ["incident", "sre"],
    "sourceUrl": "https://runbook.example.test/rto"
  }'
```

Response:

`create` and first-time `upsert` requests return `201`. `upsert` updates return `200` and preserve the existing entry ID.

```json
{
  "scope": "team",
  "mode": "created",
  "entry": {
    "id": "custom-team-550e8400-e29b-41d4-a716-446655440000",
    "term": "RTO",
    "expansion": "Recovery Time Objective",
    "meaning": "Custom definition for RTO.",
    "domains": ["incident", "sre", "runbook.example.test"],
    "sources": [
      {
        "license": "proprietary-team",
        "publisher": "wat browser extension",
        "retrieved_at": "2026-06-23T00:00:00.000Z",
        "snippet": "RTO was saved as Recovery Time Objective from the browser extension.",
        "title": "runbook.example.test",
        "url": "https://runbook.example.test/rto"
      }
    ]
  }
}
```

CORS:

- `OPTIONS /custom-entries` returns `204`.
- Allowed methods are `POST, OPTIONS`.
- Allowed request headers are `authorization, content-type, x-api-key, x-wat-team-id, x-wat-user-id`.
- Origins are deny-by-default. Configure `WAT_ALLOWED_ORIGINS` and `WAT_EXTENSION_ORIGINS` as described under `GET /search`.

Errors:

| Status | Error | Cause |
| --- | --- | --- |
| `400` | `invalid_custom_entry` | Missing or empty `term`/`expansion`, or `mode` is not `create`/`upsert`. |
| `401` | `invalid_api_key` | Supplied token does not match an active DB-backed API key. |
| `403` | `insufficient_api_scope` | API key lacks the required `write` scope. |
| `401` | `missing_user_scope` | Anonymous write or missing user scope. |
| `403` | `missing_team_scope` | Team-scope write without team scope. |
| `409` | `custom_entry_conflict` | Duplicate term/expansion or ID in that layer when `mode` is `create`. |

### `POST /suggestions`

Queue a team-scoped, DB-backed glossary suggestion. This is the Slack and Discord `/wat-suggest` write path.

Auth:

- `Authorization: Bearer $WAT_API_KEY` or `X-API-Key: $WAT_API_KEY` is required.
- `X-Wat-Team-Id` is optional and must match the authenticated key's team when supplied.
- `X-Wat-User-Id` is used for quota scope and is stored inside `after_jsonb`.
- API key must include `suggest` or `admin` scope.

Request body:

| Name         | Type     | Required | Notes                                                |
| ------------ | -------- | -------- | ---------------------------------------------------- |
| `term`       | string   | yes      | Acronym or term to suggest.                          |
| `expansion`  | string   | yes      | Suggested expansion.                                 |
| `meaning`    | string   | yes      | Suggested meaning.                                   |
| `domains`    | string[] | yes      | Team/domain context.                                 |
| `source_url` | string   | yes      | Valid URL for provenance, e.g. a Slack redirect URL. |

Example:

```sh
curl \
  -X POST 'http://localhost:3000/api/v1/suggestions' \
  -H "Authorization: Bearer $WAT_API_KEY" \
  -H "Content-Type: application/json" \
  -H "X-Wat-User-Id: slack:U123" \
  -H "X-Wat-Team-Id: team_123" \
  --data '{
    "term": "RTO",
    "expansion": "Recovery Time Objective",
    "meaning": "Maximum acceptable restore time.",
    "domains": ["example", "ops"],
    "source_url": "https://slack.com/app_redirect?channel=C123"
  }'
```

Response:

```json
{
  "suggestion": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "actor_id": null,
    "team_id": "team_123",
    "target_type": "entry",
    "target_id": null,
    "status": "pending",
    "before_jsonb": null,
    "after_jsonb": {
      "term": "RTO",
      "expansion": "Recovery Time Objective",
      "meaning": "Maximum acceptable restore time.",
      "domains": ["example", "ops"],
      "source_url": "https://slack.com/app_redirect?channel=C123",
      "actor_id": "slack:U123",
      "team_id": "team_123"
    },
    "created_at": "2026-06-25T00:00:00.000Z"
  }
}
```

## Admin List And Export Pagination

Team admin list/export endpoints accept `limit` and `cursor` query params:

- `/team/admin/entries/api`
- `/team/admin/audit/api`
- `/team/admin/review/api`
- `/team/admin/export/json`
- `/team/admin/export/csv`

JSON responses include `page.limit`, `page.total`, `page.cursor`, and `page.next_cursor`. CSV exports set `X-Page-Limit`, `X-Page-Total`, and `X-Next-Cursor` headers.

## Team Import Templates

Team admins can download import templates:

- `GET /team/admin/import/template/json`
- `GET /team/admin/import/template/csv`

`POST /team/admin/import/api` accepts either JSON shaped as `{ "entries": [...] }` or CSV using the template headers. CSV `domains` are semicolon-separated, and each CSV row imports one source.

Import authorization:

- Browser imports require a signed-in team admin session.
- API imports require `Authorization: Bearer $WAT_API_KEY` or `X-API-Key: $WAT_API_KEY`.
- Import API keys must include `admin` scope.
- `X-Wat-Team-Id` is optional for API imports and must match the key's team when supplied.
- Import responses are `{ "inserted": number, "skipped": number }`; invalid shapes return `invalid_team_import`.

## Authenticated Surface Examples

These examples use `WAT_API_BASE_URL=http://localhost:3000`, `WAT_API_KEY=wat_team_key` created from `/team/admin/api-keys`, and `WAT_TEAM_ID=team_123` as a client-side label.

### curl

```sh
curl \
  -H "Authorization: Bearer $WAT_API_KEY" \
  -H "X-Wat-User-Id: user_123" \
  -H "X-Wat-Team-Id: $WAT_TEAM_ID" \
  "$WAT_API_BASE_URL/api/v1/search?q=CAP&limit=5"
```

### Browser Extension

The extension lookup path sends the stored account email and team ID with the stored API token:

```js
const url = new URL("/api/v1/search", WAT_API_BASE_URL);
url.searchParams.set("q", "CAP");
url.searchParams.set("limit", "5");
url.searchParams.set("context", "docs.example.com");

await fetch(url, {
  headers: {
    authorization: `Bearer ${WAT_API_KEY}`,
    "x-wat-user-id": "user@example.com",
    "x-wat-team-id": WAT_TEAM_ID
  }
});
```

### Slack

Slack lookups use the configured wat API key and team ID, with the Slack user ID namespaced for user-level quotas:

```sh
curl \
  -H "Authorization: Bearer $WAT_API_KEY" \
  -H "X-Wat-User-Id: slack:U_ALICE" \
  -H "X-Wat-Team-Id: $WAT_TEAM_ID" \
  "$WAT_API_BASE_URL/api/v1/search?q=TLS&limit=5&context=docs"
```

### Microsoft Teams

Teams API-based message-extension search uses the packaged OpenAPI operation `searchGlossary` and passes one query parameter, `q`, to `/api/v1/teams/search`.

Configure the Teams API secret to send `Authorization: Bearer $WAT_API_KEY`. The web API derives `team_id` from the DB-backed key; if a trusted gateway supplies `X-Wat-Teams-Tenant-Id`, the mapped team must match that key.

Source package files live in `apps/teams/appPackage`; rendered upload output lives in `apps/teams/dist`.

#### `GET /teams/search`

Teams-ready search response for Adaptive Card rendering.

```sh
curl \
  -H "Authorization: Bearer $WAT_API_KEY" \
  "$WAT_API_BASE_URL/api/v1/teams/search?q=API"
```

Optional integration-gateway header:

- `X-Wat-Teams-Tenant-Id`: resolves `team_id` through `teams_installs`. Unknown tenants and mappings that do not match the authenticated key fail closed with `403`.

#### `POST /teams/installations`

Create or update a Microsoft tenant to wat team mapping.

```sh
curl \
  -X POST "$WAT_API_BASE_URL/api/v1/teams/installations" \
  -H "Authorization: Bearer $WAT_API_KEY" \
  -H "Content-Type: application/json" \
  -H "X-Wat-Team-Id: team_123" \
  --data '{
    "microsoft_tenant_id": "tenant_123",
    "tenant_name": "Example Tenant",
    "app_id": "teams-app-id",
    "auth_type": "apiSecretServiceAuth",
    "api_secret_registration_id": "secret-registration-id"
  }'
```

#### `DELETE /teams/installations`

Delete a Microsoft tenant mapping for the authenticated wat team.

```sh
curl \
  -X DELETE "$WAT_API_BASE_URL/api/v1/teams/installations?tenant_id=tenant_123" \
  -H "Authorization: Bearer $WAT_API_KEY" \
  -H "X-Wat-Team-Id: team_123"
```

### Discord

Discord uses a separate signed interactions runtime at `/discord/interactions`. Runtime install redirect is `/discord/install`; the web API owns guild lifecycle mapping.

#### `POST /discord/installations`

Create or update a Discord guild to wat team mapping.

```sh
curl \
  -X POST "$WAT_API_BASE_URL/api/v1/discord/installations" \
  -H "Authorization: Bearer $WAT_API_KEY" \
  -H "Content-Type: application/json" \
  -H "X-Wat-Team-Id: team_123" \
  --data '{
    "discord_guild_id": "guild_123",
    "guild_name": "Example Guild",
    "application_id": "discord-app-id",
    "bot_user_id": "bot-user-id",
    "admin_role_ids": ["role_admin"]
  }'
```

#### `DELETE /discord/installations`

Delete a Discord guild mapping for the authenticated wat team.

```sh
curl \
  -X DELETE "$WAT_API_BASE_URL/api/v1/discord/installations?guild_id=guild_123" \
  -H "Authorization: Bearer $WAT_API_KEY" \
  -H "X-Wat-Team-Id: team_123"
```

#### `GET /discord/metrics`

Protected web-side Discord lifecycle metrics.

```sh
curl -H "Authorization: Bearer $DISCORD_METRICS_TOKEN" \
  "$WAT_API_BASE_URL/api/v1/discord/metrics"
```

### MCP

MCP local stdio reads `WAT_API_BASE_URL` and `WAT_API_KEY` from its environment. Tool calls do not include credentials. See [MCP Configuration](mcp.md).

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "lookup",
    "arguments": {
      "term": "CAP",
      "context": "Kubernetes incident notes",
      "limit": 5
    }
  }
}
```

## Shared Types

Confidence tiers:

- `T1`: high confidence, canonical or multi-source
- `T2`: medium confidence, single strong source
- `T3`: low confidence or scrape-only
- `T4`: user-contributed or pending stronger review

Entry layers:

- `public`
- `team`
- `personal`

Source quality:

- `canonical`
- `secondary`
- `community`

## MCP

The MCP server exposes glossary lookup tools for agents and editors. Tool responses should return cited entries and should not fabricate definitions for unknown terms.

### `lookup(term, context?)`

Input:

```json
{
  "term": "CAP",
  "context": "Kubernetes autoscaling incident notes mention CAP and HPA",
  "limit": 5
}
```

Output:

```json
{
  "matches": [
    {
      "id": "seed-cap-consistency-availability-partition-tolerance",
      "term": "CAP",
      "expansion": "Consistency, Availability, Partition tolerance",
      "domains": ["distributed-systems"],
      "confidence_tier": "T2",
      "layer": "public",
      "sources": [
        {
          "title": "CAP theorem",
          "url": "https://en.wikipedia.org/wiki/CAP_theorem",
          "publisher": "Wikipedia",
          "license": "CC-BY-SA-4.0"
        }
      ]
    }
  ]
}
```

No-match output:

```json
{
  "matches": [],
  "suggest_url": "/suggest?term=CAPX"
}
```

### `list_team_acronyms(domain?)`

Input:

```json
{
  "domain": "infra",
  "cursor": null,
  "limit": 50
}
```

Output:

```json
{
  "entries": [
    {
      "id": "team-slo-service-level-objective",
      "term": "SLO",
      "expansions": ["Service Level Objective"],
      "domains": ["reliability", "infra"],
      "confidence_tier": "T4",
      "layer": "team"
    }
  ],
  "next_cursor": null
}
```

## Errors

REST endpoints use HTTP status codes and return `{ error, code, message, request_id }` on failures. Validation failures should return `400`, unauthorized requests `401`, forbidden requests `403`, rate limits `429`, and unexpected failures `500`.

## Webhooks

Set `WAT_WEBHOOK_URL` and `WAT_WEBHOOK_SECRET` to receive signed team-entry events:

- `team_entry.created`
- `team_entry.updated`

Each delivery is a JSON POST with:

- `X-Wat-Event`: event type
- `X-Wat-Timestamp`: Unix timestamp seconds
- `X-Wat-Signature`: `sha256=` plus HMAC-SHA256 of `<timestamp>.<raw body>` using `WAT_WEBHOOK_SECRET`

Webhook delivery is non-blocking for entry writes. Receivers should reject stale timestamps and verify the signature before processing.

MCP tools should return structured tool errors with the same categories: validation, unauthorized, forbidden, rate_limited, and internal.
