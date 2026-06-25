import { randomUUID } from "node:crypto";

import { authDb } from "@/lib/auth-db";
import type { SuggestedEdit, SuggestedEntryInput } from "@/lib/suggestions";

export type DbSuggestion = SuggestedEdit;

export interface CreateDbSuggestionInput {
  actorId: string;
  suggestion: SuggestedEntryInput;
  teamId: string;
}

function rowToSuggestion(row: {
  actor_id: string | null;
  after_jsonb: unknown;
  before_jsonb: unknown | null;
  created_at: Date;
  id: string;
  status: "pending";
  target_id: string | null;
  target_type: "entry";
  team_id: string;
}): DbSuggestion {
  return {
    actor_id: row.actor_id,
    after_jsonb: row.after_jsonb,
    before_jsonb: row.before_jsonb,
    created_at: row.created_at.toISOString(),
    id: row.id,
    status: row.status,
    target_id: row.target_id,
    target_type: row.target_type,
    team_id: row.team_id
  };
}

export async function createDbSuggestion({
  actorId,
  suggestion,
  teamId
}: CreateDbSuggestionInput): Promise<DbSuggestion> {
  const id = randomUUID();
  const afterJsonb = { ...suggestion, actor_id: actorId, team_id: teamId };
  const { rows } = await authDb().query<{
    actor_id: string | null;
    after_jsonb: unknown;
    before_jsonb: unknown | null;
    created_at: Date;
    id: string;
    status: "pending";
    target_id: string | null;
    target_type: "entry";
    team_id: string;
  }>(
    `
    insert into suggested_edits (
      id, actor_id, team_id, target_type, target_id, before_jsonb, after_jsonb
    ) values ($1, null, $2, 'entry', null, null, $3::jsonb)
    returning id, actor_id, team_id, target_type, target_id, status, before_jsonb, after_jsonb, created_at
    `,
    [id, teamId, JSON.stringify(afterJsonb)]
  );
  const row = rows[0];
  if (!row) throw new Error("suggestion insert failed");
  return rowToSuggestion(row);
}
