# Teams Store Checklist

## Package

- Render with `pnpm --filter @wat/teams package:prod`.
- Upload `apps/teams/dist/wat-teams-app.zip`.
- Confirm `manifestVersion` is `1.17`.
- Confirm `composeExtensionType` is `apiBased`.
- Confirm command ID `searchGlossary` matches OpenAPI `operationId`.
- Confirm command parameter `q` matches the OpenAPI query parameter.
- Confirm `response-template.json` uses `jsonPath: results`.
- Confirm `color.png` is 192x192 and `outline.png` is 32x32.

## Developer Portal

- Register the API secret and set `TEAMS_API_SECRET_REGISTRATION_ID`.
- Set `TEAMS_PUBLIC_ORIGIN` to the production HTTPS wat origin.
- Set `TEAMS_APP_ID` to the app GUID from Developer Portal.
- Configure the API secret value to a DB-backed wat team API key with `search` scope.

## Demo Script

1. Add the app to a test chat or team.
2. Open the compose message area.
3. Select the wat message extension.
4. Search `API`.
5. Select a result and confirm the card renders term, expansion, meaning, layer, and confidence.
6. Repeat from the command box.
7. Confirm `/api/v1/teams/metrics` increments `teams_search_total`.

## Data Handling

- The search command sends only the typed `q` parameter.
- No channel history, selected message text, or passive message content is requested.
- API-secret auth is read-only and should map to one wat team until Entra SSO or bot auth lands.
- Optional `X-Wat-Teams-Tenant-Id` mapping is for trusted gateways or later SSO/bot flows.

## Support Links

- Privacy: `/privacy`
- Terms: `/terms`
- Security model: `docs/security-model.md`
- Teams runbook: `docs/teams.md`
