import { authDb } from "@/lib/auth-db";

export interface DiscordInstallRecord {
  admin_role_ids: string[];
  application_id: string;
  bot_user_id: string | null;
  discord_guild_id: string;
  guild_name: string | null;
  id: string;
  installed_at: string;
  installer_discord_user_id: string | null;
  team_id: string;
  updated_at: string;
}

export interface UpsertDiscordInstallInput {
  adminRoleIds?: string[];
  applicationId: string;
  botUserId?: string;
  discordGuildId: string;
  guildName?: string;
  installerDiscordUserId?: string;
  teamId: string;
}

export async function upsertDiscordInstall(
  input: UpsertDiscordInstallInput
): Promise<DiscordInstallRecord> {
  const id = `discord-install-${input.discordGuildId.toLowerCase()}`;
  const { rows } = await authDb().query<DiscordInstallRow>(
    `
    insert into discord_installs (
      id, discord_guild_id, guild_name, team_id, application_id,
      bot_user_id, installer_discord_user_id, admin_role_ids
    ) values ($1, $2, $3, $4, $5, $6, $7, $8)
    on conflict (discord_guild_id) do update set
      guild_name = excluded.guild_name,
      team_id = excluded.team_id,
      application_id = excluded.application_id,
      bot_user_id = excluded.bot_user_id,
      installer_discord_user_id = excluded.installer_discord_user_id,
      admin_role_ids = excluded.admin_role_ids,
      updated_at = now()
    returning
      id, discord_guild_id, guild_name, team_id, application_id, bot_user_id,
      installer_discord_user_id, admin_role_ids, installed_at, updated_at
    `,
    [
      id,
      input.discordGuildId,
      input.guildName ?? null,
      input.teamId,
      input.applicationId,
      input.botUserId ?? null,
      input.installerDiscordUserId ?? null,
      input.adminRoleIds ?? []
    ]
  );
  const row = rows[0];
  if (!row) throw new Error("Discord install upsert failed");
  return discordInstallFromRow(row);
}

export async function getDiscordInstallByGuildId(
  discordGuildId: string
): Promise<DiscordInstallRecord | null> {
  const { rows } = await authDb().query<DiscordInstallRow>(
    `
    select
      id, discord_guild_id, guild_name, team_id, application_id, bot_user_id,
      installer_discord_user_id, admin_role_ids, installed_at, updated_at
    from discord_installs
    where discord_guild_id = $1
    `,
    [discordGuildId]
  );
  return rows[0] ? discordInstallFromRow(rows[0]) : null;
}

export async function deleteDiscordInstallByGuildId(
  discordGuildId: string,
  teamId: string
): Promise<boolean> {
  const { rowCount } = await authDb().query(
    "delete from discord_installs where discord_guild_id = $1 and team_id = $2",
    [discordGuildId, teamId]
  );
  return (rowCount ?? 0) > 0;
}

interface DiscordInstallRow {
  admin_role_ids: string[];
  application_id: string;
  bot_user_id: string | null;
  discord_guild_id: string;
  guild_name: string | null;
  id: string;
  installed_at: Date | string;
  installer_discord_user_id: string | null;
  team_id: string;
  updated_at: Date | string;
}

function discordInstallFromRow(row: DiscordInstallRow): DiscordInstallRecord {
  return {
    admin_role_ids: row.admin_role_ids,
    application_id: row.application_id,
    bot_user_id: row.bot_user_id,
    discord_guild_id: row.discord_guild_id,
    guild_name: row.guild_name,
    id: row.id,
    installed_at: timestampString(row.installed_at),
    installer_discord_user_id: row.installer_discord_user_id,
    team_id: row.team_id,
    updated_at: timestampString(row.updated_at)
  };
}

function timestampString(value: Date | string): string {
  return value instanceof Date ? value.toISOString() : value;
}
