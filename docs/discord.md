# Discord

Discord support is an HTTP interactions runtime, not a gateway bot loop.

## Current Support

- Ed25519 signature validation for `X-Signature-Ed25519` and `X-Signature-Timestamp`.
- PING/PONG endpoint validation at `POST /discord/interactions`.
- `/wat`, `/wat-alt`, `/wat-suggest`, and `/wat-define` slash commands.
- `Explain acronyms` message command.
- Ephemeral responses and disabled mention parsing.
- DB-backed guild mapping through `discord_installs`.
- JSON and memory install stores for local development.
- Protected runtime `/metrics`.
- Command registration script for guild or global command overwrite.

## Runtime Env

```sh
DISCORD_PUBLIC_KEY=<application-public-key>
DISCORD_APPLICATION_ID=<application-id>
DISCORD_BOT_TOKEN=<bot-token>
DISCORD_INSTALL_SCOPES=applications.commands
DISCORD_INSTALL_GUILD_ID=
DISCORD_INSTALL_DISABLE_GUILD_SELECT=false
DISCORD_INSTALL_INTEGRATION_TYPE=0
DISCORD_INSTALL_STORE=postgres
DISCORD_DATABASE_URL=<postgres-url>
DISCORD_METRICS_TOKEN=<random-secret>
DISCORD_ADMIN_USER_IDS=
DISCORD_ADMIN_ROLE_IDS=
WAT_API_BASE_URL=https://wat.example.com
WAT_API_KEY=<team-api-key>
WAT_DISCORD_GUILD_MAP=
WAT_TEAM_ID=
```

`DISCORD_PUBLIC_KEY` is required at runtime. `DISCORD_BOT_TOKEN` is only required for command registration. `WAT_API_KEY` must be a DB-backed team API key; if `WAT_TEAM_ID` is used as a fallback, it must match that key's team.

## Install Flow

1. Create a Discord application and copy the application ID and public key.
2. Deploy `@wat/discord` behind HTTPS.
3. Set the Discord Interactions Endpoint URL to `https://<host>/discord/interactions`.
4. Register commands with `pnpm --filter @wat/discord commands:register`.
5. Install the app into a guild through `https://<host>/discord/install`.
6. Write the guild mapping through `/api/v1/discord/installations`.
7. Smoke-test `/wat API`, `/wat-suggest`, and an admin-only `/wat-define`.

## Guild Mapping API

```sh
curl -X POST "$WAT_API_BASE_URL/api/v1/discord/installations" \
  -H "Authorization: Bearer $WAT_API_KEY" \
  -H "Content-Type: application/json" \
  -H "X-Wat-Team-Id: team_123" \
  --data '{"discord_guild_id":"guild_123","guild_name":"Example Guild","application_id":"discord-app-id","admin_role_ids":["role_admin"]}'
```

Delete:

```sh
curl -X DELETE "$WAT_API_BASE_URL/api/v1/discord/installations?guild_id=guild_123" \
  -H "Authorization: Bearer $WAT_API_KEY" \
  -H "X-Wat-Team-Id: team_123"
```

## Admin Model

`/wat-define` is allowed when one of these is true:

- Discord member has Administrator permission.
- Discord user ID is in `DISCORD_ADMIN_USER_IDS`.
- Discord member role intersects `DISCORD_ADMIN_ROLE_IDS` or the install record's `admin_role_ids`.

Discord does not provide member email in interactions, so wat team-admin checks by email are not available on this surface.

## Verification

```sh
pnpm --filter @wat/discord test
pnpm --filter @wat/discord build
pnpm --filter @wat/discord commands:print
curl -f "$DISCORD_PUBLIC_URL/healthz"
curl -f -H "Authorization: Bearer $DISCORD_METRICS_TOKEN" "$DISCORD_PUBLIC_URL/metrics"
```
