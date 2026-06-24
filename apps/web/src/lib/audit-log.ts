import { randomUUID } from "node:crypto";

export interface AuditLogEntry {
  action: string;
  actor_id: string;
  after_jsonb: unknown;
  at: string;
  before_jsonb: unknown;
  id: string;
  target_id: string;
  target_type: string;
}

const auditLog: AuditLogEntry[] = [];

export function recordAuditLog(input: Omit<AuditLogEntry, "at" | "id">): AuditLogEntry {
  const entry: AuditLogEntry = {
    ...input,
    at: new Date().toISOString(),
    id: randomUUID()
  };
  auditLog.push(structuredClone(entry));
  return structuredClone(entry);
}

export function getAuditLog(): AuditLogEntry[] {
  return structuredClone(auditLog);
}

export function listAuditLogPage(offset: number, limit: number): {
  audit: AuditLogEntry[];
  total: number;
} {
  return {
    audit: structuredClone(auditLog.slice(offset, offset + limit)),
    total: auditLog.length
  };
}

export function resetAuditLogForTest() {
  auditLog.length = 0;
}
