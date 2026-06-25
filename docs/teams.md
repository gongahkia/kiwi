# Microsoft Teams

wat's Teams surface starts with an API-based message extension for search.

## Scope

Current support:

- Teams app manifest source in `apps/teams/appPackage/manifest.json`.
- OpenAPI Description for `GET /api/v1/teams/search`.
- Adaptive Card response template for search results.
- Package renderer and validator in `apps/teams/scripts`.
- DB-backed tenant mapping in `teams_installs`.
- Protected Teams metrics at `/api/v1/teams/metrics`.
- Generated upload ZIP at `apps/teams/dist/wat-teams-app.zip`.

Not included yet:

- Entra SSO.
- Per-tenant DB mapping.
- Bot-based message extensions.
- Define/suggest/admin write flows.

API-based message extensions only support search commands, so this should stay read-only until a bot or SSO-backed flow is added.

## Render Package

```sh
TEAMS_PUBLIC_ORIGIN=https://wat.example.com \
TEAMS_APP_ID=<teams-app-guid> \
TEAMS_API_SECRET_REGISTRATION_ID=<secret-registration-guid> \
pnpm --filter @wat/teams package:prod
```

Output:

- `apps/teams/dist/appPackage`
- `apps/teams/dist/wat-teams-app.zip`

## Backend Config

For self-host/single-team installs:

```sh
WAT_API_KEY=<same-secret-registered-in-teams-developer-portal>
WAT_TEAM_ID=team_123
TEAMS_METRICS_TOKEN=<random-secret>
```

Teams API-secret auth sends `Authorization: Bearer <secret>` to wat. If `X-Wat-Team-Id` is absent, wat API-key identity falls back to `WAT_TEAM_ID`.

For integration gateways or later SSO/bot flows that can supply a Microsoft tenant ID, create a DB mapping:

```sh
curl \
  -X POST "$TEAMS_PUBLIC_ORIGIN/api/v1/teams/installations" \
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

## Upload

1. Create or open the Teams app in Developer Portal.
2. Configure API-based message extension.
3. Register the API secret and copy the registration ID into `TEAMS_API_SECRET_REGISTRATION_ID`.
4. Upload `apps/teams/dist/wat-teams-app.zip`.
5. Add the app to a test chat/team.
6. From compose or command box, search `API`.

## Verification

Local package checks:

```sh
pnpm --filter @wat/teams test
```

API smoke test:

```sh
curl \
  -H "Authorization: Bearer $WAT_API_KEY" \
  "$TEAMS_PUBLIC_ORIGIN/api/v1/teams/search?q=API"
```

Metrics smoke test:

```sh
curl \
  -H "Authorization: Bearer $TEAMS_METRICS_TOKEN" \
  "$TEAMS_PUBLIC_ORIGIN/api/v1/teams/metrics"
```

Expected response shape:

```json
{
  "results": [
    {
      "term": "API",
      "expansion": "Application Programming Interface",
      "title": "API: Application Programming Interface"
    }
  ]
}
```

## References

- https://learn.microsoft.com/en-us/microsoftteams/platform/messaging-extensions/create-api-message-extension
- https://learn.microsoft.com/en-us/microsoftteams/platform/concepts/build-and-test/apps-package
