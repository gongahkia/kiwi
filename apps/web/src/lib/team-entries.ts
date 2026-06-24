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

const privateSourceLicenses = new Set([
  "internal",
  "proprietary-personal",
  "proprietary-team",
  "unknown"
]);

function nonEmpty(value: string): boolean {
  return value.trim().length > 0;
}

function validUrl(value: string): boolean {
  try {
    new URL(value);
    return true;
  } catch {
    return false;
  }
}

function isGeneratedSourceUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.hostname === "wat.local";
  } catch {
    return false;
  }
}

function validateSource(source: unknown): string | null {
  if (!source || typeof source !== "object") return "source fields are required";
  const candidate = source as Partial<TeamEntrySource>;
  const sourceValues = [
    candidate.license,
    candidate.publisher,
    candidate.retrieved_at,
    candidate.snippet,
    candidate.title,
    candidate.url
  ];
  if (sourceValues.some((value) => typeof value !== "string" || !nonEmpty(value))) {
    return "source fields are required";
  }
  if (!validUrl(candidate.url!)) return "source url must be valid";
  if (Number.isNaN(Date.parse(candidate.retrieved_at!))) {
    return "source retrieved_at must be valid";
  }
  if (!privateSourceLicenses.has(candidate.license!) && isGeneratedSourceUrl(candidate.url!)) {
    return "public-compatible source license requires an external source url";
  }

  return null;
}

export function validateTeamEntry(entry: TeamEntry): string[] {
  const issues: string[] = [];
  if (!nonEmpty(entry.id)) issues.push("id is required");
  if (!nonEmpty(entry.term)) issues.push("term is required");
  if (!nonEmpty(entry.expansion)) issues.push("expansion is required");
  if (!nonEmpty(entry.meaning)) issues.push("meaning is required");
  if (!entry.domains.every(nonEmpty)) issues.push("domains are required");
  if (entry.sources.length === 0) issues.push("at least one source is required");

  for (const [index, source] of entry.sources.entries()) {
    const issue = validateSource(source);
    if (issue) issues.push(`source ${index}: ${issue}`);
  }

  return issues;
}

function assertValidTeamEntry(entry: TeamEntry): void {
  const issues = validateTeamEntry(entry);
  if (issues.length > 0) {
    throw new Error(`invalid team entry: ${issues.join("; ")}`);
  }
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

export function listTeamEntriesPage(offset: number, limit: number): {
  entries: TeamEntry[];
  total: number;
} {
  return {
    entries: structuredClone(teamEntries.slice(offset, offset + limit)),
    total: teamEntries.length
  };
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
    assertValidTeamEntry(entry);
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
  assertValidTeamEntry(entry);
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
  assertValidTeamEntry(entry);

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
