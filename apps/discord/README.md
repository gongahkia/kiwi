# wat Discord App

Signed Discord interactions runtime for slash and message-command glossary workflows.

## Commands

- `/wat term:<term>`: lookup, ephemeral by default.
- `/wat-alt term:<term>`: alternatives from contemporaries.
- `/wat-suggest term:<term> expansion:<expansion> meaning:<meaning>`: queues a team-scoped suggestion.
- `/wat-define term:<term> expansion:<expansion> meaning:<meaning>`: upserts a team entry for configured admins.
- `Explain acronyms`: message command that extracts uppercase acronyms and looks them up.

## Configure

```sh
DISCORD_PUBLIC_KEY=<application-public-key>
DISCORD_APPLICATION_ID=<application-id>
DISCORD_BOT_TOKEN=<bot-token>
DISCORD_INSTALL_SCOPES=applications.commands
DISCORD_INSTALL_STORE=postgres
DISCORD_DATABASE_URL=postgres://wat:wat@localhost:5432/wat
DISCORD_METRICS_TOKEN=<random-secret>
WAT_API_BASE_URL=http://localhost:3000
WAT_API_KEY=<self-host-dev-key>
WAT_DISCORD_GUILD_MAP=<discord-guild-id>:team_123
```

Set the Discord Interactions Endpoint URL to:

```text
https://<discord-runtime-host>/discord/interactions
```

Open the install redirect when adding the app to a guild:

```sh
open http://localhost:3002/discord/install
```

## Register Commands

Guild-scoped registration updates faster during staging:

```sh
DISCORD_GUILD_ID=<guild-id> pnpm --filter @wat/discord commands:register
```

Omit `DISCORD_GUILD_ID` for global production registration.

## Guild Mapping

Preferred production mapping is `discord_installs`, written through the web API:

```sh
curl -X POST "$WAT_API_BASE_URL/api/v1/discord/installations" \
  -H "Authorization: Bearer $WAT_API_KEY" \
  -H "Content-Type: application/json" \
  -H "X-Wat-Team-Id: team_123" \
  --data '{"discord_guild_id":"guild_123","guild_name":"Example Guild","application_id":"discord-app-id","admin_role_ids":["role_admin"]}'
```

`WAT_DISCORD_GUILD_MAP=guild_123:team_123` remains the self-host fallback.

## Verify

```sh
pnpm --filter @wat/discord build
pnpm --filter @wat/discord test
pnpm --filter @wat/discord commands:print
curl -f http://localhost:3002/healthz
curl -f -H "Authorization: Bearer $DISCORD_METRICS_TOKEN" http://localhost:3002/metrics
```
