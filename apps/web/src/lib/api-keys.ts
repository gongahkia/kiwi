import { createHash, randomBytes, randomUUID } from "node:crypto";

import { authDb } from "@/lib/auth-db";

export type ApiKeyScope = "admin" | "search" | "suggest" | "write";

export interface ApiKeyRecord {
  created_at: string;
  created_by: string | null;
  id: string;
  key_prefix: string;
  last_used_at: string | null;
  name: string;
  revoked_at: string | null;
  scopes: ApiKeyScope[];
  team_id: string;
}

export interface CreatedApiKey extends ApiKeyRecord {
  key: string;
}

const defaultScopes: ApiKeyScope[] = ["admin", "search", "suggest", "write"];

const testKeys = new Map<string, ApiKeyRecord>();

export function hashApiKey(key: string): string {
  return createHash("sha256").update(key).digest("hex");
}

function keyPrefix(key: string): string {
  return key.slice(0, 14);
}

function assertScopes(scopes: ApiKeyScope[]): ApiKeyScope[] {
  const valid = new Set<ApiKeyScope>(["admin", "search", "suggest", "write"]);
  const unique = Array.from(new Set(scopes));
  if (unique.length === 0 || unique.some((scope) => !valid.has(scope))) {
    throw new Error("invalid api key scopes");
  }
  return unique;
}

function rowToRecord(row: {
  created_at: Date;
  created_by: string | null;
  id: string;
  key_prefix: string;
  last_used_at: Date | null;
  name: string;
  revoked_at: Date | null;
  scopes: ApiKeyScope[];
  team_id: string;
}): ApiKeyRecord {
  return {
    created_at: row.created_at.toISOString(),
    created_by: row.created_by,
    id: row.id,
    key_prefix: row.key_prefix,
    last_used_at: row.last_used_at?.toISOString() ?? null,
    name: row.name,
    revoked_at: row.revoked_at?.toISOString() ?? null,
    scopes: row.scopes,
    team_id: row.team_id
  };
}

export async function createApiKey(input: {
  createdBy: string | null;
  name: string;
  scopes?: ApiKeyScope[];
  teamId: string;
}): Promise<CreatedApiKey> {
  const key = `wat_${randomBytes(32).toString("base64url")}`;
  const scopes = assertScopes(input.scopes ?? defaultScopes);
  const { rows } = await authDb().query<{
    created_at: Date;
    created_by: string | null;
    id: string;
    key_prefix: string;
    last_used_at: Date | null;
    name: string;
    revoked_at: Date | null;
    scopes: ApiKeyScope[];
    team_id: string;
  }>(
    `
    insert into api_keys (id, team_id, name, key_prefix, key_hash, scopes, created_by)
    values ($1, $2, $3, $4, $5, $6, $7)
    returning id, team_id, name, key_prefix, scopes, created_by, created_at, last_used_at, revoked_at
    `,
    [
      randomUUID(),
      input.teamId,
      input.name.trim() || "Team API key",
      keyPrefix(key),
      hashApiKey(key),
      scopes,
      input.createdBy
    ]
  );
  const row = rows[0];
  if (!row) throw new Error("api key create failed");
  return { ...rowToRecord(row), key };
}

export async function listApiKeys(teamId: string): Promise<ApiKeyRecord[]> {
  const { rows } = await authDb().query<{
    created_at: Date;
    created_by: string | null;
    id: string;
    key_prefix: string;
    last_used_at: Date | null;
    name: string;
    revoked_at: Date | null;
    scopes: ApiKeyScope[];
    team_id: string;
  }>(
    `
    select id, team_id, name, key_prefix, scopes, created_by, created_at, last_used_at, revoked_at
    from api_keys
    where team_id = $1
    order by created_at desc
    `,
    [teamId]
  );
  return rows.map(rowToRecord);
}

export async function revokeApiKey(teamId: string, id: string): Promise<ApiKeyRecord> {
  const { rows } = await authDb().query<{
    created_at: Date;
    created_by: string | null;
    id: string;
    key_prefix: string;
    last_used_at: Date | null;
    name: string;
    revoked_at: Date | null;
    scopes: ApiKeyScope[];
    team_id: string;
  }>(
    `
    update api_keys
    set revoked_at = now()
    where team_id = $1 and id = $2 and revoked_at is null
    returning id, team_id, name, key_prefix, scopes, created_by, created_at, last_used_at, revoked_at
    `,
    [teamId, id]
  );
  const row = rows[0];
  if (!row) throw new Error("api key not found");
  return rowToRecord(row);
}

export async function lookupApiKey(key: string): Promise<ApiKeyRecord | null> {
  if (process.env.NODE_ENV === "test") {
    const testRecord = testKeys.get(hashApiKey(key));
    return testRecord && !testRecord.revoked_at ? structuredClone(testRecord) : null;
  }

  const { rows } = await authDb().query<{
    created_at: Date;
    created_by: string | null;
    id: string;
    key_prefix: string;
    last_used_at: Date | null;
    name: string;
    revoked_at: Date | null;
    scopes: ApiKeyScope[];
    team_id: string;
  }>(
    `
    update api_keys
    set last_used_at = now()
    where key_hash = $1 and revoked_at is null
    returning id, team_id, name, key_prefix, scopes, created_by, created_at, last_used_at, revoked_at
    `,
    [hashApiKey(key)]
  );
  return rows[0] ? rowToRecord(rows[0]) : null;
}

export function seedApiKeyForTest(
  input: {
    key?: string;
    name?: string;
    scopes?: ApiKeyScope[];
    teamId?: string;
  } = {}
): string {
  const key = input.key ?? "test-key";
  const now = new Date().toISOString();
  testKeys.set(hashApiKey(key), {
    created_at: now,
    created_by: "user_admin",
    id: `test-api-key-${hashApiKey(key).slice(0, 8)}`,
    key_prefix: keyPrefix(key),
    last_used_at: null,
    name: input.name ?? "Test API key",
    revoked_at: null,
    scopes: input.scopes ?? defaultScopes,
    team_id: input.teamId ?? "team_1"
  });
  return key;
}

export function resetApiKeysForTest(): void {
  testKeys.clear();
}
