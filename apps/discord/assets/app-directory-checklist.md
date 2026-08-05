# Discord Integration Checklist

- Discord application has Interactions Endpoint URL set to `/discord/interactions`.
- Install URL points admins at `/discord/install` or the Discord-provided install link.
- Endpoint passes Discord PING validation with Ed25519 signature verification enabled.
- Slash commands are registered from `apps/discord/src/discord-commands.ts`.
- `wat-define` defaults to Administrator permission and runtime role/user allowlists are configured.
- Guild-to-team mapping exists in `discord_installs` or `WAT_DISCORD_GUILD_MAP`.
- `DISCORD_INSTALL_STORE=postgres` is used outside local development.
- `/metrics` is protected by `DISCORD_METRICS_TOKEN`.
- `/wat-suggest` creates a `suggested_edits` row with `team_id`.
- `/wat-define` sends `scope=team`, `mode=upsert`, and `X-Wat-Team-Id`.
- Response content uses `allowed_mentions.parse=[]` and ephemeral responses by default.
