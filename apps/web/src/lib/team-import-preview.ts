import { parseTeamImportCsv } from "./team-import-template";
import { validateTeamEntry, type TeamEntry } from "./team-entries";

export type TeamImportFormat = "csv" | "json";

export interface TeamImportIssue {
  entryId: string;
  message: string;
}

export interface TeamImportPreview {
  accepted: TeamEntry[];
  issues: TeamImportIssue[];
  total: number;
}

function idFor(entry: Partial<TeamEntry>, index: number): string {
  return typeof entry.id === "string" && entry.id.trim() ? entry.id.trim() : `row ${index + 1}`;
}

function entriesFromJson(input: string): TeamEntry[] | null {
  const parsed = JSON.parse(input) as { entries?: unknown };
  return Array.isArray(parsed.entries) ? (parsed.entries as TeamEntry[]) : null;
}

export function previewTeamImport(input: string, format: TeamImportFormat): TeamImportPreview {
  if (!input.trim()) return { accepted: [], issues: [], total: 0 };

  try {
    const entries = format === "csv" ? parseTeamImportCsv(input) : entriesFromJson(input);
    if (!entries) {
      return {
        accepted: [],
        issues: [{ entryId: "file", message: `invalid ${format} import shape` }],
        total: 0
      };
    }

    const accepted: TeamEntry[] = [];
    const issues: TeamImportIssue[] = [];

    entries.forEach((entry, index) => {
      const entryIssues = validateTeamEntry(entry);
      if (entryIssues.length > 0) {
        issues.push({ entryId: idFor(entry, index), message: entryIssues.join("; ") });
      } else {
        accepted.push(entry);
      }
    });

    return { accepted, issues, total: entries.length };
  } catch (error) {
    return {
      accepted: [],
      issues: [
        {
          entryId: "file",
          message: error instanceof Error ? error.message : `invalid ${format} import`
        }
      ],
      total: 0
    };
  }
}
