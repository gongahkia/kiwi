# API

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

API clients can pass a configured token with either `Authorization: Bearer $WAT_API_KEY` or `X-API-Key: $WAT_API_KEY`. Token requests can also send `X-Wat-User-Id` and `X-Wat-Team-Id` so quotas apply per user and team.

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

REST endpoints use HTTP status codes. Validation failures should return `400`, unauthorized requests `401`, forbidden requests `403`, rate limits `429`, and unexpected failures `500`.

MCP tools should return structured tool errors with the same categories: validation, unauthorized, forbidden, rate_limited, and internal.
