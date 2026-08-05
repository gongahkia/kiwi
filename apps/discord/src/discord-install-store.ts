import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { Pool } from "pg";

export interface DiscordInstallRecord {
  adminRoleIds: string[];
  appId: string;
  botUserId?: string;
  discordGuildId: string;
  guildName?: string;
  installedAt: string;
  installerDiscordUserId?: string;
  updatedAt: string;
  watTeamId: string;
}

export interface DiscordInstallStore {
  deleteByGuildId(discordGuildId: string): Promise<void>;
  getByGuildId(discordGuildId: string): Promise<DiscordInstallRecord | null>;
  upsert(record: DiscordInstallRecord): Promise<void>;
}

export class MemoryDiscordInstallStore implements DiscordInstallStore {
  private readonly records = new Map<string, DiscordInstallRecord>();

  async deleteByGuildId(discordGuildId: string): Promise<void> {
    this.records.delete(discordGuildId);
  }

  async getByGuildId(discordGuildId: string): Promise<DiscordInstallRecord | null> {
    const record = this.records.get(discordGuildId);
    return record ? structuredClone(record) : null;
  }

  async upsert(record: DiscordInstallRecord): Promise<void> {
    this.records.set(record.discordGuildId, structuredClone(record));
  }
}

export class JsonFileDiscordInstallStore implements DiscordInstallStore {
  constructor(private readonly path: string) {}

  async deleteByGuildId(discordGuildId: string): Promise<void> {
    const records = await this.readRecords();
    records.delete(discordGuildId);
    await this.writeRecords(records);
  }

  async getByGuildId(discordGuildId: string): Promise<DiscordInstallRecord | null> {
    const records = await this.readRecords();
    const record = records.get(discordGuildId);
    return record ? structuredClone(record) : null;
  }

  async upsert(record: DiscordInstallRecord): Promise<void> {
    const records = await this.readRecords();
    records.set(record.discordGuildId, structuredClone(record));
    await this.writeRecords(records);
  }

  private async readRecords(): Promise<Map<string, DiscordInstallRecord>> {
    try {
      const body = JSON.parse(await readFile(this.path, "utf8")) as unknown;
      const installs =
        body && typeof body === "object" && Array.isArray((body as { installs?: unknown }).installs)
          ? (body as { installs: unknown[] }).installs
          : [];
      return new Map(
        installs
          .filter(isDiscordInstallRecord)
          .map((record) => [record.discordGuildId, structuredClone(record)])
      );
    } catch (error) {
      if (isNodeError(error) && error.code === "ENOENT") return new Map();
      throw error;
    }
  }

  private async writeRecords(records: Map<string, DiscordInstallRecord>): Promise<void> {
    await mkdir(dirname(this.path), { recursive: true });
    const tempPath = `${this.path}.${process.pid}.${Date.now()}.tmp`;
    const body = JSON.stringify(
      { installs: Array.from(records.values()).sort(byGuildId) },
      null,
      2
    );
    await writeFile(tempPath, `${body}\n`, "utf8");
    await rename(tempPath, this.path);
  }
}

interface QueryResult<Row> {
  rows: Row[];
}

interface PgQueryable {
  query<Row>(sql: string, values?: unknown[]): Promise<QueryResult<Row>>;
}

interface DiscordInstallRow {
  admin_role_ids: string[];
  application_id: string;
  bot_user_id: string | null;
  discord_guild_id: string;
  guild_name: string | null;
  installed_at: Date | string;
  installer_discord_user_id: string | null;
  team_id: string;
  updated_at: Date | string;
}

export class PgDiscordInstallStore implements DiscordInstallStore {
  private readonly client: PgQueryable;

  constructor(connection: string | PgQueryable) {
    this.client =
      typeof connection === "string" ? new Pool({ connectionString: connection }) : connection;
  }

  async deleteByGuildId(discordGuildId: string): Promise<void> {
    await this.client.query("delete from discord_installs where discord_guild_id = $1", [
      discordGuildId
    ]);
  }

  async getByGuildId(discordGuildId: string): Promise<DiscordInstallRecord | null> {
    const result = await this.client.query<DiscordInstallRow>(
      `
      select
        admin_role_ids,
        application_id,
        bot_user_id,
        discord_guild_id,
        guild_name,
        installed_at,
        installer_discord_user_id,
        team_id,
        updated_at
      from discord_installs
      where discord_guild_id = $1
      `,
      [discordGuildId]
    );
    return result.rows[0] ? rowToRecord(result.rows[0]) : null;
  }

  async upsert(record: DiscordInstallRecord): Promise<void> {
    await this.client.query(
      `
      insert into discord_installs (
        id,
        discord_guild_id,
        guild_name,
        team_id,
        application_id,
        bot_user_id,
        installer_discord_user_id,
        admin_role_ids,
        installed_at,
        updated_at
      ) values (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
      )
      on conflict (discord_guild_id) do update set
        guild_name = excluded.guild_name,
        team_id = excluded.team_id,
        application_id = excluded.application_id,
        bot_user_id = excluded.bot_user_id,
        installer_discord_user_id = excluded.installer_discord_user_id,
        admin_role_ids = excluded.admin_role_ids,
        updated_at = excluded.updated_at
      `,
      [
        `discord-install-${record.discordGuildId.toLowerCase()}`,
        record.discordGuildId,
        record.guildName ?? null,
        record.watTeamId,
        record.appId,
        record.botUserId ?? null,
        record.installerDiscordUserId ?? null,
        record.adminRoleIds,
        record.installedAt,
        record.updatedAt
      ]
    );
  }
}

function byGuildId(left: DiscordInstallRecord, right: DiscordInstallRecord): number {
  return left.discordGuildId.localeCompare(right.discordGuildId);
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}

function isDiscordInstallRecord(value: unknown): value is DiscordInstallRecord {
  if (!value || typeof value !== "object") return false;
  const record = value as Partial<DiscordInstallRecord>;
  return (
    Array.isArray(record.adminRoleIds) &&
    record.adminRoleIds.every((item) => typeof item === "string") &&
    typeof record.appId === "string" &&
    typeof record.discordGuildId === "string" &&
    typeof record.installedAt === "string" &&
    typeof record.updatedAt === "string" &&
    typeof record.watTeamId === "string"
  );
}

function rowToRecord(row: DiscordInstallRow): DiscordInstallRecord {
  return {
    adminRoleIds: row.admin_role_ids,
    appId: row.application_id,
    botUserId: row.bot_user_id ?? undefined,
    discordGuildId: row.discord_guild_id,
    guildName: row.guild_name ?? undefined,
    installedAt: timestampString(row.installed_at),
    installerDiscordUserId: row.installer_discord_user_id ?? undefined,
    updatedAt: timestampString(row.updated_at),
    watTeamId: row.team_id
  };
}

function timestampString(value: Date | string): string {
  return value instanceof Date ? value.toISOString() : value;
}
