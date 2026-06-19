import { recordAuditLog, type AuditLogEntry } from "./audit-log";
import { createTeamEntry, getTeamEntries, updateTeamEntry, type TeamEntry } from "./team-entries";
import type { SuggestedEdit, SuggestedEntryInput } from "./suggestions";

export interface ApprovalResult {
  audit: AuditLogEntry;
  entry: TeamEntry;
}

function slug(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

function isNewEntryPayload(value: unknown): value is SuggestedEntryInput {
  if (!value || typeof value !== "object") return false;
  const input = value as Partial<SuggestedEntryInput>;
  return (
    typeof input.term === "string" &&
    typeof input.expansion === "string" &&
    typeof input.meaning === "string" &&
    typeof input.source_url === "string" &&
    Array.isArray(input.domains)
  );
}

function teamEntryFromSuggestion(suggestion: SuggestedEdit, input: SuggestedEntryInput): TeamEntry {
  return {
    domains: input.domains,
    expansion: input.expansion,
    id: `team-suggested-${slug(input.term)}-${suggestion.id.slice(0, 8)}`,
    meaning: input.meaning,
    sources: [
      {
        license: "MIT",
        publisher: "wat suggestion",
        retrieved_at: suggestion.created_at,
        snippet: input.meaning,
        title: `${input.term} suggested source`,
        url: input.source_url
      }
    ],
    term: input.term
  };
}

export function approveSuggestion(suggestion: SuggestedEdit, reviewerId: string): ApprovalResult {
  if (suggestion.target_id === null && isNewEntryPayload(suggestion.after_jsonb)) {
    const entry = createTeamEntry(teamEntryFromSuggestion(suggestion, suggestion.after_jsonb));
    const audit = recordAuditLog({
      action: "suggestion.approve.create",
      actor_id: reviewerId,
      after_jsonb: entry,
      before_jsonb: null,
      target_id: entry.id,
      target_type: "team_entry"
    });
    return { audit, entry };
  }

  const existing = getTeamEntries().find((entry) => entry.id === suggestion.target_id);
  if (!suggestion.target_id || !existing || typeof suggestion.after_jsonb !== "object") {
    throw new Error("suggestion cannot be applied");
  }

  const entry = updateTeamEntry(suggestion.target_id, suggestion.after_jsonb as Partial<TeamEntry>);
  const audit = recordAuditLog({
    action: "suggestion.approve.update",
    actor_id: reviewerId,
    after_jsonb: entry,
    before_jsonb: existing,
    target_id: entry.id,
    target_type: "team_entry"
  });
  return { audit, entry };
}
