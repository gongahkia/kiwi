# wat Teams App

API-based Teams message extension for glossary search.

## Install Shape

The first Teams surface is search-only. API-based message extensions only support search commands, so define/suggest/admin flows should wait for bot or SSO work.

Package files:

- `appPackage/manifest.json`: Teams app manifest using `composeExtensionType: apiBased`.
- `appPackage/wat-openapi.yml`: OpenAPI Description for `GET /api/v1/search`.
- `appPackage/response-template.json`: Adaptive Card rendering template for search results.
- `appPackage/color.png` and `appPackage/outline.png`: package icons.
- `assets/store-checklist.md`: Teams review and production checklist.

## Configure

For a real package, render from environment:

```sh
TEAMS_PUBLIC_ORIGIN=https://wat.example.com
TEAMS_APP_ID=<teams-app-guid>
TEAMS_API_SECRET_REGISTRATION_ID=<developer-portal-secret-registration-guid>
pnpm --filter @wat/teams package:prod
```

This writes `apps/teams/dist/appPackage` and `apps/teams/dist/wat-teams-app.zip`.

Teams calls the OpenAPI operation `searchGlossary` with one query parameter, `q`, against `/api/v1/teams/search`. Configure the API secret registration to send a DB-backed team API key generated in wat admin. The web API derives team identity from that key.

## Verify

```sh
pnpm --filter @wat/teams test
pnpm --filter @wat/teams package
pnpm --filter @wat/teams package:prod
```

Then upload `apps/teams/dist/wat-teams-app.zip` through Teams Developer Portal or Microsoft 365 Agents Toolkit.
