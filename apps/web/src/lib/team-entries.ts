export interface TeamEntrySource {
  license: string;
  publisher: string;
  retrieved_at: string;
  snippet: string;
  title: string;
  url: string;
}

export interface TeamEntry {
  domains: string[];
  expansion: string;
  id: string;
  meaning: string;
  sources: TeamEntrySource[];
  term: string;
}

export const initialTeamEntries: TeamEntry[] = [
  {
    domains: ["example.com", "platform"],
    expansion: "Change Approval Process",
    id: "team-example-cap",
    meaning: "Internal release-gating process for production-impacting changes.",
    sources: [
      {
        license: "proprietary-team",
        publisher: "wat dev fixture",
        retrieved_at: "2026-06-19T00:00:00.000Z",
        snippet: "CAP is the release-gating review for production-impacting changes.",
        title: "example.com team glossary fixture",
        url: "https://example.com/glossary/cap"
      }
    ],
    term: "CAP"
  },
  {
    domains: ["example.com", "ops"],
    expansion: "Deployment Freeze",
    id: "team-example-df",
    meaning: "Internal freeze window where production deploys require incident-lead approval.",
    sources: [
      {
        license: "proprietary-team",
        publisher: "wat dev fixture",
        retrieved_at: "2026-06-19T00:00:00.000Z",
        snippet: "DF marks a deploy freeze window for production systems.",
        title: "example.com deployment glossary fixture",
        url: "https://example.com/glossary/df"
      }
    ],
    term: "DF"
  }
];

let teamEntries = structuredClone(initialTeamEntries);

export function getTeamEntries(): TeamEntry[] {
  return structuredClone(teamEntries);
}

export function resetTeamEntriesForTest() {
  teamEntries = structuredClone(initialTeamEntries);
}

function importKey(entry: TeamEntry): string {
  return `${entry.term.trim().toLowerCase()}:${entry.expansion.trim().toLowerCase()}`;
}

export function importTeamEntries(entries: TeamEntry[]): {
  inserted: TeamEntry[];
  skipped: TeamEntry[];
} {
  const existing = new Set(teamEntries.map(importKey));
  const inserted: TeamEntry[] = [];
  const skipped: TeamEntry[] = [];

  for (const entry of entries) {
    const key = importKey(entry);
    if (existing.has(key)) {
      skipped.push(entry);
      continue;
    }

    teamEntries.push(structuredClone(entry));
    existing.add(key);
    inserted.push(entry);
  }

  return { inserted, skipped };
}

export function createTeamEntry(entry: TeamEntry): TeamEntry {
  const key = importKey(entry);
  if (teamEntries.some((item) => importKey(item) === key || item.id === entry.id)) {
    throw new Error("team entry already exists");
  }

  teamEntries.push(structuredClone(entry));
  return structuredClone(entry);
}

export function updateTeamEntry(entryId: string, patch: Partial<TeamEntry>): TeamEntry {
  const entry = teamEntries.find((item) => item.id === entryId);
  if (!entry) {
    throw new Error("team entry not found");
  }

  if (patch.term?.trim()) entry.term = patch.term.trim();
  if (patch.expansion?.trim()) entry.expansion = patch.expansion.trim();
  if (patch.meaning?.trim()) entry.meaning = patch.meaning.trim();
  if (patch.domains) entry.domains = patch.domains;
  if (patch.sources) entry.sources = patch.sources;

  return structuredClone(entry);
}

export function deleteTeamEntry(entryId: string): TeamEntry {
  const index = teamEntries.findIndex((entry) => entry.id === entryId);
  if (index === -1) {
    throw new Error("team entry not found");
  }

  const [removed] = teamEntries.splice(index, 1);
  if (!removed) {
    throw new Error("team entry not found");
  }

  return structuredClone(removed);
}

function csvCell(value: string): string {
  return `"${value.replaceAll('"', '""')}"`;
}

export function teamEntriesCsv(entries = getTeamEntries()): string {
  const header = ["id", "term", "expansion", "meaning", "domains", "sources"];
  const rows = entries.map((entry) =>
    [
      entry.id,
      entry.term,
      entry.expansion,
      entry.meaning,
      entry.domains.join(";"),
      entry.sources.map((source) => source.url).join(";")
    ]
      .map(csvCell)
      .join(",")
  );

  return `${header.join(",")}\n${rows.join("\n")}\n`;
}
