import type { TeamEntry } from "./team-entries";
import { validateTeamEntry } from "./team-entries";

function entryKey(entry: Pick<TeamEntry, "expansion" | "term">): string {
  return `${entry.term.trim().toLowerCase()}:${entry.expansion.trim().toLowerCase()}`;
}

export function validateTeamEntryDraft(
  entry: TeamEntry,
  existingEntries: TeamEntry[],
  editingId = ""
): string[] {
  const issues = validateTeamEntry(entry);
  const comparableEntries = existingEntries.filter((existing) => existing.id !== editingId);
  const key = entryKey(entry);

  if (entry.id.trim() && comparableEntries.some((existing) => existing.id === entry.id)) {
    issues.push("duplicate id");
  }

  if (
    entry.term.trim() &&
    entry.expansion.trim() &&
    comparableEntries.some((existing) => entryKey(existing) === key)
  ) {
    issues.push("duplicate term and expansion");
  }

  return Array.from(new Set(issues));
}
