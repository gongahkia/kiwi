import { randomUUID } from "node:crypto";

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
  actor_id: string;
  after_jsonb: unknown;
  before_jsonb: unknown | null;
  created_at: string;
  id: string;
  reviewed_at?: string;
  reviewed_by?: string;
  status: SuggestedEditStatus;
  target_id: string | null;
  target_type: SuggestedTargetType;
}

const suggestedEdits: SuggestedEdit[] = [];

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

export function submitNewEntrySuggestion(
  actorId: string,
  input: SuggestedEntryInput
): SuggestedEdit {
  const suggestion: SuggestedEdit = {
    actor_id: actorId,
    after_jsonb: input,
    before_jsonb: null,
    created_at: new Date().toISOString(),
    id: randomUUID(),
    status: "pending",
    target_id: null,
    target_type: "entry"
  };
  suggestedEdits.push(structuredClone(suggestion));
  return structuredClone(suggestion);
}

export function submitEntryEditSuggestion(
  actorId: string,
  targetId: string,
  input: SuggestedEntryEditInput,
  before: unknown = null
): SuggestedEdit {
  const suggestion: SuggestedEdit = {
    actor_id: actorId,
    after_jsonb: input,
    before_jsonb: before,
    created_at: new Date().toISOString(),
    id: randomUUID(),
    status: "pending",
    target_id: targetId,
    target_type: "entry"
  };
  suggestedEdits.push(structuredClone(suggestion));
  return structuredClone(suggestion);
}

export function reviewSuggestedEdit(
  suggestionId: string,
  reviewerId: string,
  status: SuggestedEditStatus,
  afterJsonb?: unknown
): SuggestedEdit {
  const suggestion = suggestedEdits.find((item) => item.id === suggestionId);
  if (!suggestion) {
    throw new Error("suggestion not found");
  }

  suggestion.status = status;
  suggestion.reviewed_by = reviewerId;
  suggestion.reviewed_at = new Date().toISOString();
  suggestion.after_jsonb = afterJsonb ?? suggestion.after_jsonb;
  return structuredClone(suggestion);
}

export function getSuggestedEdits(): SuggestedEdit[] {
  return structuredClone(suggestedEdits);
}

export function resetSuggestedEditsForTest() {
  suggestedEdits.length = 0;
}
