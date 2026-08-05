import { randomUUID } from "node:crypto";

import { authDb } from "@/lib/auth-db";

export type SuggestedEditStatus = "approved" | "pending" | "rejected";
export type SuggestedTargetType = "entry";

export interface SuggestedEntryInput {
  domains: string[];
  expansion: string;
  meaning: string;
  source_url: string;
  term: string;
}

export interface SuggestedEntryEditInput {
  expansion: string;
  meaning: string;
  source_url: string;
}

export interface SuggestedEdit {
  actor_id: string | null;
  after_jsonb: unknown;
  before_jsonb: unknown | null;
  created_at: string;
  id: string;
  reviewed_at?: string;
  reviewed_by?: string | null;
  status: SuggestedEditStatus;
  target_id: string | null;
  target_type: SuggestedTargetType;
  team_id: string | null;
}

const testSuggestedEdits: SuggestedEdit[] = [];

function useTestState(): boolean {
  return process.env.NODE_ENV === "test";
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function validUrl(value: string): boolean {
  try {
    new URL(value);
    return true;
  } catch {
    return false;
  }
}

function rowToSuggestion(row: {
  actor_id: string | null;
  after_jsonb: unknown;
  before_jsonb: unknown | null;
  created_at: Date;
  id: string;
  reviewed_at: Date | null;
  reviewed_by: string | null;
  status: SuggestedEditStatus;
  target_id: string | null;
  target_type: SuggestedTargetType;
  team_id: string | null;
}): SuggestedEdit {
  return {
    actor_id: row.actor_id,
    after_jsonb: row.after_jsonb,
    before_jsonb: row.before_jsonb,
    created_at: row.created_at.toISOString(),
    id: row.id,
    reviewed_at: row.reviewed_at?.toISOString(),
    reviewed_by: row.reviewed_by,
    status: row.status,
    target_id: row.target_id,
    target_type: row.target_type,
    team_id: row.team_id
  };
}

export function validateSuggestedEntry(value: unknown): SuggestedEntryInput | null {
  if (!value || typeof value !== "object") return null;
  const input = value as Partial<SuggestedEntryInput>;
  if (
    !nonEmptyString(input.term) ||
    !nonEmptyString(input.expansion) ||
    !nonEmptyString(input.meaning) ||
    !nonEmptyString(input.source_url) ||
    !validUrl(input.source_url) ||
    !Array.isArray(input.domains) ||
    input.domains.some((domain) => !nonEmptyString(domain))
  ) {
    return null;
  }
  return {
    domains: input.domains.map((domain) => domain.trim()),
    expansion: input.expansion.trim(),
    meaning: input.meaning.trim(),
    source_url: input.source_url.trim(),
    term: input.term.trim()
  };
}

export function validateSuggestedEntryEdit(value: unknown): SuggestedEntryEditInput | null {
  if (!value || typeof value !== "object") return null;
  const input = value as Partial<SuggestedEntryEditInput>;
  if (
    !nonEmptyString(input.expansion) ||
    !nonEmptyString(input.meaning) ||
    !nonEmptyString(input.source_url) ||
    !validUrl(input.source_url)
  ) {
    return null;
  }
  return {
    expansion: input.expansion.trim(),
    meaning: input.meaning.trim(),
    source_url: input.source_url.trim()
  };
}

async function insertSuggestion(input: {
  actorId: string | null;
  afterJsonb: unknown;
  beforeJsonb: unknown | null;
  targetId: string | null;
  teamId: string | null;
}): Promise<SuggestedEdit> {
  const suggestion: SuggestedEdit = {
    actor_id: input.actorId,
    after_jsonb: input.afterJsonb,
    before_jsonb: input.beforeJsonb,
    created_at: new Date().toISOString(),
    id: randomUUID(),
    status: "pending",
    target_id: input.targetId,
    target_type: "entry",
    team_id: input.teamId
  };
  if (useTestState()) {
    testSuggestedEdits.push(structuredClone(suggestion));
    return structuredClone(suggestion);
  }
  const { rows } = await authDb().query<{
    actor_id: string | null;
    after_jsonb: unknown;
    before_jsonb: unknown | null;
    created_at: Date;
    id: string;
    reviewed_at: Date | null;
    reviewed_by: string | null;
    status: SuggestedEditStatus;
    target_id: string | null;
    target_type: SuggestedTargetType;
    team_id: string | null;
  }>(
    `
    insert into suggested_edits (
      id, actor_id, team_id, target_type, target_id, before_jsonb, after_jsonb
    ) values ($1, $2, $3, 'entry', $4, $5::jsonb, $6::jsonb)
    returning id, actor_id, team_id, target_type, target_id, status, before_jsonb, after_jsonb, created_at, reviewed_by, reviewed_at
    `,
    [
      suggestion.id,
      input.actorId,
      input.teamId,
      input.targetId,
      JSON.stringify(input.beforeJsonb),
      JSON.stringify(input.afterJsonb)
    ]
  );
  const row = rows[0];
  if (!row) throw new Error("suggestion insert failed");
  return rowToSuggestion(row);
}

export function suggestionAfterJson(input: SuggestedEntryInput, actorId: string, teamId: string) {
  return { ...input, actor_id: actorId, team_id: teamId };
}

export async function submitNewEntrySuggestion(
  teamId: string | null,
  actorId: string | null,
  input: SuggestedEntryInput
): Promise<SuggestedEdit> {
  return insertSuggestion({
    actorId,
    afterJsonb: teamId && actorId ? suggestionAfterJson(input, actorId, teamId) : input,
    beforeJsonb: null,
    targetId: null,
    teamId
  });
}

export async function submitEntryEditSuggestion(
  teamId: string | null,
  actorId: string,
  targetId: string,
  input: SuggestedEntryEditInput,
  before: unknown = null
): Promise<SuggestedEdit> {
  return insertSuggestion({
    actorId,
    afterJsonb: input,
    beforeJsonb: before,
    targetId,
    teamId
  });
}

export async function reviewSuggestedEdit(
  teamId: string,
  suggestionId: string,
  reviewerId: string,
  status: SuggestedEditStatus,
  afterJsonb?: unknown
): Promise<SuggestedEdit> {
  if (useTestState()) {
    const suggestion = testSuggestedEdits.find(
      (item) => item.id === suggestionId && item.team_id === teamId
    );
    if (!suggestion) throw new Error("suggestion not found");
    suggestion.status = status;
    suggestion.reviewed_by = reviewerId;
    suggestion.reviewed_at = new Date().toISOString();
    suggestion.after_jsonb = afterJsonb ?? suggestion.after_jsonb;
    return structuredClone(suggestion);
  }
  const { rows } = await authDb().query<{
    actor_id: string | null;
    after_jsonb: unknown;
    before_jsonb: unknown | null;
    created_at: Date;
    id: string;
    reviewed_at: Date | null;
    reviewed_by: string | null;
    status: SuggestedEditStatus;
    target_id: string | null;
    target_type: SuggestedTargetType;
    team_id: string | null;
  }>(
    `
    update suggested_edits
    set status = $3, reviewed_by = $4, reviewed_at = now(), after_jsonb = coalesce($5::jsonb, after_jsonb)
    where team_id = $1 and id = $2
    returning id, actor_id, team_id, target_type, target_id, status, before_jsonb, after_jsonb, created_at, reviewed_by, reviewed_at
    `,
    [
      teamId,
      suggestionId,
      status,
      reviewerId,
      afterJsonb == null ? null : JSON.stringify(afterJsonb)
    ]
  );
  const row = rows[0];
  if (!row) throw new Error("suggestion not found");
  return rowToSuggestion(row);
}

export async function getSuggestedEdits(teamId?: string): Promise<SuggestedEdit[]> {
  if (useTestState()) {
    return structuredClone(
      teamId ? testSuggestedEdits.filter((item) => item.team_id === teamId) : testSuggestedEdits
    );
  }
  const { rows } = await authDb().query<{
    actor_id: string | null;
    after_jsonb: unknown;
    before_jsonb: unknown | null;
    created_at: Date;
    id: string;
    reviewed_at: Date | null;
    reviewed_by: string | null;
    status: SuggestedEditStatus;
    target_id: string | null;
    target_type: SuggestedTargetType;
    team_id: string | null;
  }>(
    `
    select id, actor_id, team_id, target_type, target_id, status, before_jsonb, after_jsonb, created_at, reviewed_by, reviewed_at
    from suggested_edits
    where ($1::text is null or team_id = $1)
    order by created_at desc
    `,
    [teamId ?? null]
  );
  return rows.map(rowToSuggestion);
}

export async function listSuggestedEditsPage(
  teamId: string,
  offset: number,
  limit: number
): Promise<{ suggestions: SuggestedEdit[]; total: number }> {
  if (useTestState()) {
    const suggestions = testSuggestedEdits.filter((item) => item.team_id === teamId);
    return {
      suggestions: structuredClone(suggestions.slice(offset, offset + limit)),
      total: suggestions.length
    };
  }
  const [{ rows }, count] = await Promise.all([
    authDb().query<{
      actor_id: string | null;
      after_jsonb: unknown;
      before_jsonb: unknown | null;
      created_at: Date;
      id: string;
      reviewed_at: Date | null;
      reviewed_by: string | null;
      status: SuggestedEditStatus;
      target_id: string | null;
      target_type: SuggestedTargetType;
      team_id: string | null;
    }>(
      `
      select id, actor_id, team_id, target_type, target_id, status, before_jsonb, after_jsonb, created_at, reviewed_by, reviewed_at
      from suggested_edits
      where team_id = $1
      order by created_at desc
      offset $2 limit $3
      `,
      [teamId, offset, limit]
    ),
    authDb().query<{ count: string }>(
      "select count(*)::text as count from suggested_edits where team_id = $1",
      [teamId]
    )
  ]);
  return {
    suggestions: rows.map(rowToSuggestion),
    total: Number(count.rows[0]?.count ?? 0)
  };
}

export function resetSuggestedEditsForTest(): void {
  testSuggestedEdits.length = 0;
}
