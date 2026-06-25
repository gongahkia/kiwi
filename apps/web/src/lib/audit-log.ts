import { randomUUID } from "node:crypto";

import { authDb } from "@/lib/auth-db";

export interface AuditLogEntry {
  action: string;
  actor_id: string;
  after_jsonb: unknown;
  at: string;
  before_jsonb: unknown;
  id: string;
  target_id: string;
  target_type: string;
  team_id: string | null;
}

const testAuditLog: AuditLogEntry[] = [];

function useTestState(): boolean {
  return process.env.NODE_ENV === "test";
}

function rowToAudit(row: {
  action: string;
  actor_id: string | null;
  after_jsonb: unknown;
  at: Date;
  before_jsonb: unknown;
  id: string;
  target_id: string;
  target_type: string;
  team_id: string | null;
}): AuditLogEntry {
  return {
    action: row.action,
    actor_id: row.actor_id ?? "system",
    after_jsonb: row.after_jsonb,
    at: row.at.toISOString(),
    before_jsonb: row.before_jsonb,
    id: row.id,
    target_id: row.target_id,
    target_type: row.target_type,
    team_id: row.team_id
  };
}

export async function recordAuditLog(
  input: Omit<AuditLogEntry, "at" | "id">
): Promise<AuditLogEntry> {
  if (useTestState()) {
    const entry: AuditLogEntry = { ...input, at: new Date().toISOString(), id: randomUUID() };
    testAuditLog.push(structuredClone(entry));
    return structuredClone(entry);
  }
  const id = randomUUID();
  const { rows } = await authDb().query<{
    action: string;
    actor_id: string | null;
    after_jsonb: unknown;
    at: Date;
    before_jsonb: unknown;
    id: string;
    target_id: string;
    target_type: string;
    team_id: string | null;
  }>(
    `
    insert into audit_log (
      id, actor_id, team_id, action, target_type, target_id, before_jsonb, after_jsonb
    ) values ($1, $2, $3, $4, $5, $6, $7::jsonb, $8::jsonb)
    returning id, actor_id, team_id, action, target_type, target_id, before_jsonb, after_jsonb, at
    `,
    [
      id,
      input.actor_id,
      input.team_id,
      input.action,
      input.target_type,
      input.target_id,
      JSON.stringify(input.before_jsonb),
      JSON.stringify(input.after_jsonb)
    ]
  );
  const row = rows[0];
  if (!row) throw new Error("audit insert failed");
  return rowToAudit(row);
}

export async function getAuditLog(teamId?: string): Promise<AuditLogEntry[]> {
  if (useTestState()) {
    return structuredClone(
      teamId ? testAuditLog.filter((entry) => entry.team_id === teamId) : testAuditLog
    );
  }
  const { rows } = await authDb().query<{
    action: string;
    actor_id: string | null;
    after_jsonb: unknown;
    at: Date;
    before_jsonb: unknown;
    id: string;
    target_id: string;
    target_type: string;
    team_id: string | null;
  }>(
    `
    select id, actor_id, team_id, action, target_type, target_id, before_jsonb, after_jsonb, at
    from audit_log
    where ($1::text is null or team_id = $1)
    order by at desc
    `,
    [teamId ?? null]
  );
  return rows.map(rowToAudit);
}

export async function listAuditLogPage(
  teamId: string,
  offset: number,
  limit: number
): Promise<{ audit: AuditLogEntry[]; total: number }> {
  if (useTestState()) {
    const audit = testAuditLog.filter((entry) => entry.team_id === teamId);
    return {
      audit: structuredClone(audit.slice(offset, offset + limit)),
      total: audit.length
    };
  }
  const [{ rows }, count] = await Promise.all([
    authDb().query<{
      action: string;
      actor_id: string | null;
      after_jsonb: unknown;
      at: Date;
      before_jsonb: unknown;
      id: string;
      target_id: string;
      target_type: string;
      team_id: string | null;
    }>(
      `
      select id, actor_id, team_id, action, target_type, target_id, before_jsonb, after_jsonb, at
      from audit_log
      where team_id = $1
      order by at desc
      offset $2 limit $3
      `,
      [teamId, offset, limit]
    ),
    authDb().query<{ count: string }>(
      "select count(*)::text as count from audit_log where team_id = $1",
      [teamId]
    )
  ]);
  return {
    audit: rows.map(rowToAudit),
    total: Number(count.rows[0]?.count ?? 0)
  };
}

export function resetAuditLogForTest(): void {
  testAuditLog.length = 0;
}
