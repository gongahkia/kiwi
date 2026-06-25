import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { Pool } from "pg";

import type { EncryptedToken } from "./token-encryption.js";

export interface SlackInstallRecord {
  appId: string;
  botScopes: string[];
  botToken: EncryptedToken;
  botUserId: string;
  enterpriseId?: string;
  enterpriseName?: string;
  installedAt: string;
  installerSlackUserId: string;
  slackTeamId: string;
  slackTeamName?: string;
  updatedAt: string;
  userScopes: string[];
  userToken?: EncryptedToken;
  watTeamId: string;
}

export interface SlackInstallStore {
  deleteBySlackTeamId(slackTeamId: string): Promise<void>;
  getBySlackTeamId(slackTeamId: string): Promise<SlackInstallRecord | null>;
  upsert(record: SlackInstallRecord): Promise<void>;
}

export class MemorySlackInstallStore implements SlackInstallStore {
  private readonly records = new Map<string, SlackInstallRecord>();

  async deleteBySlackTeamId(slackTeamId: string): Promise<void> {
    this.records.delete(slackTeamId);
  }

  async getBySlackTeamId(slackTeamId: string): Promise<SlackInstallRecord | null> {
    const record = this.records.get(slackTeamId);
    return record ? structuredClone(record) : null;
  }

  async upsert(record: SlackInstallRecord): Promise<void> {
    this.records.set(record.slackTeamId, structuredClone(record));
  }
}

export class JsonFileSlackInstallStore implements SlackInstallStore {
  constructor(private readonly path: string) {}

  async deleteBySlackTeamId(slackTeamId: string): Promise<void> {
    const records = await this.readRecords();
    records.delete(slackTeamId);
    await this.writeRecords(records);
  }

  async getBySlackTeamId(slackTeamId: string): Promise<SlackInstallRecord | null> {
    const records = await this.readRecords();
    const record = records.get(slackTeamId);
    return record ? structuredClone(record) : null;
  }

  async upsert(record: SlackInstallRecord): Promise<void> {
    const records = await this.readRecords();
    records.set(record.slackTeamId, structuredClone(record));
    await this.writeRecords(records);
  }

  private async readRecords(): Promise<Map<string, SlackInstallRecord>> {
    try {
      const body = JSON.parse(await readFile(this.path, "utf8")) as unknown;
      const installs =
        body && typeof body === "object" && Array.isArray((body as { installs?: unknown }).installs)
          ? (body as { installs: unknown[] }).installs
          : [];
      return new Map(
        installs
          .filter(isSlackInstallRecord)
          .map((record) => [record.slackTeamId, structuredClone(record)])
      );
    } catch (error) {
      if (isNodeError(error) && error.code === "ENOENT") return new Map();
      throw error;
    }
  }

  private async writeRecords(records: Map<string, SlackInstallRecord>): Promise<void> {
    await mkdir(dirname(this.path), { recursive: true });
    const tempPath = `${this.path}.${process.pid}.${Date.now()}.tmp`;
    const body = JSON.stringify(
      { installs: Array.from(records.values()).sort(bySlackTeamId) },
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

interface SlackInstallRow {
  app_id: string;
  bot_scopes: string[];
  bot_token_encrypted: unknown;
  bot_user_id: string;
  enterprise_id: string | null;
  enterprise_name: string | null;
  installed_at: Date | string;
  installer_slack_user_id: string;
  slack_team_id: string;
  slack_team_name: string | null;
  team_id: string;
  updated_at: Date | string;
  user_scopes: string[];
  user_token_encrypted: unknown;
}

export class PgSlackInstallStore implements SlackInstallStore {
  private readonly client: PgQueryable;

  constructor(connection: string | PgQueryable) {
    this.client =
      typeof connection === "string" ? new Pool({ connectionString: connection }) : connection;
  }

  async deleteBySlackTeamId(slackTeamId: string): Promise<void> {
    await this.client.query("delete from slack_installs where slack_team_id = $1", [slackTeamId]);
  }

  async getBySlackTeamId(slackTeamId: string): Promise<SlackInstallRecord | null> {
    const result = await this.client.query<SlackInstallRow>(
      `
      select
        app_id,
        bot_scopes,
        bot_token_encrypted,
        bot_user_id,
        enterprise_id,
        enterprise_name,
        installed_at,
        installer_slack_user_id,
        slack_team_id,
        slack_team_name,
        team_id,
        updated_at,
        user_scopes,
        user_token_encrypted
      from slack_installs
      where slack_team_id = $1
      `,
      [slackTeamId]
    );
    return result.rows[0] ? rowToRecord(result.rows[0]) : null;
  }

  async upsert(record: SlackInstallRecord): Promise<void> {
    await this.client.query(
      `
      insert into slack_installs (
        id,
        slack_team_id,
        slack_team_name,
        enterprise_id,
        enterprise_name,
        team_id,
        app_id,
        bot_user_id,
        installer_slack_user_id,
        bot_token_encrypted,
        user_token_encrypted,
        bot_scopes,
        user_scopes,
        installed_at,
        updated_at
      ) values (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, $11::jsonb, $12, $13, $14, $15
      )
      on conflict (slack_team_id) do update set
        slack_team_name = excluded.slack_team_name,
        enterprise_id = excluded.enterprise_id,
        enterprise_name = excluded.enterprise_name,
        team_id = excluded.team_id,
        app_id = excluded.app_id,
        bot_user_id = excluded.bot_user_id,
        installer_slack_user_id = excluded.installer_slack_user_id,
        bot_token_encrypted = excluded.bot_token_encrypted,
        user_token_encrypted = excluded.user_token_encrypted,
        bot_scopes = excluded.bot_scopes,
        user_scopes = excluded.user_scopes,
        updated_at = excluded.updated_at
      `,
      [
        `slack-install-${record.slackTeamId.toLowerCase()}`,
        record.slackTeamId,
        record.slackTeamName ?? null,
        record.enterpriseId ?? null,
        record.enterpriseName ?? null,
        record.watTeamId,
        record.appId,
        record.botUserId,
        record.installerSlackUserId,
        JSON.stringify(record.botToken),
        record.userToken ? JSON.stringify(record.userToken) : null,
        record.botScopes,
        record.userScopes,
        record.installedAt,
        record.updatedAt
      ]
    );
  }
}

function bySlackTeamId(left: SlackInstallRecord, right: SlackInstallRecord): number {
  return left.slackTeamId.localeCompare(right.slackTeamId);
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}

function isSlackInstallRecord(value: unknown): value is SlackInstallRecord {
  if (!value || typeof value !== "object") return false;
  const record = value as Partial<SlackInstallRecord>;
  return (
    typeof record.appId === "string" &&
    Array.isArray(record.botScopes) &&
    isEncryptedToken(record.botToken) &&
    typeof record.botUserId === "string" &&
    typeof record.installedAt === "string" &&
    typeof record.installerSlackUserId === "string" &&
    typeof record.slackTeamId === "string" &&
    typeof record.updatedAt === "string" &&
    Array.isArray(record.userScopes) &&
    typeof record.watTeamId === "string"
  );
}

function isEncryptedToken(value: unknown): value is EncryptedToken {
  if (!value || typeof value !== "object") return false;
  const token = value as Partial<EncryptedToken>;
  return (
    typeof token.ciphertext === "string" &&
    typeof token.iv === "string" &&
    typeof token.tag === "string" &&
    token.version === 1
  );
}

function rowToRecord(row: SlackInstallRow): SlackInstallRecord {
  return {
    appId: row.app_id,
    botScopes: row.bot_scopes,
    botToken: encryptedTokenFrom(row.bot_token_encrypted),
    botUserId: row.bot_user_id,
    enterpriseId: row.enterprise_id ?? undefined,
    enterpriseName: row.enterprise_name ?? undefined,
    installedAt: timestampString(row.installed_at),
    installerSlackUserId: row.installer_slack_user_id,
    slackTeamId: row.slack_team_id,
    slackTeamName: row.slack_team_name ?? undefined,
    updatedAt: timestampString(row.updated_at),
    userScopes: row.user_scopes,
    userToken: row.user_token_encrypted ? encryptedTokenFrom(row.user_token_encrypted) : undefined,
    watTeamId: row.team_id
  };
}

function encryptedTokenFrom(value: unknown): EncryptedToken {
  if (!isEncryptedToken(value)) throw new Error("invalid encrypted Slack token payload");
  return structuredClone(value);
}

function timestampString(value: Date | string): string {
  return value instanceof Date ? value.toISOString() : value;
}
