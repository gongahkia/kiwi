import { parseTeamImportCsv } from "./team-import-template";
import { validateTeamEntry, type TeamEntry } from "./team-entries";

export type TeamImportFormat = "csv" | "json";

export interface TeamImportIssue {
  entryId: string;
  message: string;
}

export interface TeamImportPreview {
  accepted: TeamEntry[];
  conflicts: TeamImportPreviewConflict[];
  issues: TeamImportIssue[];
  rows: TeamImportPreviewRow[];
  total: number;
}

export interface TeamImportPreviewConflict {
  entryId: string;
  existingId: string;
  reason: "id" | "term_expansion";
}

export interface TeamImportPreviewRow {
  conflict?: TeamImportPreviewConflict;
  entry: TeamEntry;
}

function idFor(entry: Partial<TeamEntry>, index: number): string {
  return typeof entry.id === "string" && entry.id.trim() ? entry.id.trim() : `row ${index + 1}`;
}

function entriesFromJson(input: string): TeamEntry[] | null {
  const parsed = JSON.parse(input) as { entries?: unknown };
  return Array.isArray(parsed.entries) ? (parsed.entries as TeamEntry[]) : null;
}

function entryKey(entry: Pick<TeamEntry, "expansion" | "term">): string {
  return `${entry.term.trim().toLowerCase()}:${entry.expansion.trim().toLowerCase()}`;
}

function conflictFor(
  entry: TeamEntry,
  existingById: Map<string, TeamEntry>,
  existingByKey: Map<string, TeamEntry>
): TeamImportPreviewConflict | undefined {
  const idMatch = existingById.get(entry.id);
  if (idMatch) {
    return { entryId: entry.id, existingId: idMatch.id, reason: "id" };
  }

  const keyMatch = existingByKey.get(entryKey(entry));
  if (keyMatch) {
    return { entryId: entry.id, existingId: keyMatch.id, reason: "term_expansion" };
  }

  return undefined;
}

export function previewTeamImport(
  input: string,
  format: TeamImportFormat,
  existingEntries: TeamEntry[] = []
): TeamImportPreview {
  if (!input.trim()) return { accepted: [], conflicts: [], issues: [], rows: [], total: 0 };

  try {
    const entries = format === "csv" ? parseTeamImportCsv(input) : entriesFromJson(input);
    if (!entries) {
      return {
        accepted: [],
        conflicts: [],
        issues: [{ entryId: "file", message: `invalid ${format} import shape` }],
        rows: [],
        total: 0
      };
    }

    const accepted: TeamEntry[] = [];
    const rows: TeamImportPreviewRow[] = [];
    const issues: TeamImportIssue[] = [];
    const existingById = new Map(existingEntries.map((entry) => [entry.id, entry]));
    const existingByKey = new Map(existingEntries.map((entry) => [entryKey(entry), entry]));

    entries.forEach((entry, index) => {
      const entryIssues = validateTeamEntry(entry);
      if (entryIssues.length > 0) {
        issues.push({ entryId: idFor(entry, index), message: entryIssues.join("; ") });
      } else {
        accepted.push(entry);
        rows.push({ conflict: conflictFor(entry, existingById, existingByKey), entry });
      }
    });

    return {
      accepted,
      conflicts: rows.flatMap((row) => (row.conflict ? [row.conflict] : [])),
      issues,
      rows,
      total: entries.length
    };
  } catch (error) {
    return {
      accepted: [],
      conflicts: [],
      issues: [
        {
          entryId: "file",
          message: error instanceof Error ? error.message : `invalid ${format} import`
        }
      ],
      rows: [],
      total: 0
    };
  }
}
