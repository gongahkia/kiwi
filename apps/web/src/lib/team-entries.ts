import { randomUUID } from "node:crypto";
import type { PoolClient } from "pg";

import { authDb } from "@/lib/auth-db";

export interface TeamEntrySource {
  license: string;
  publisher: string;
  retrieved_at: string;
  snippet: string;
  title: string;
  url: string;
}

export interface TeamEntry {
  contemporaries?: string[];
  domains: string[];
  expansion: string;
  id: string;
  meaning: string;
  sources: TeamEntrySource[];
  term: string;
}

type EntryRow = {
  contemporaries: string[];
  domains: string[];
  expansions: string[];
  id: string;
  meaning_short: string;
  term: string;
};

type SourceRow = {
  entry_id: string;
  license: string;
  publisher: string;
  retrieved_at: Date;
  snippet: string;
  title: string;
  url: string;
};

const privateSourceLicenses = new Set([
  "internal",
  "proprietary-personal",
  "proprietary-team",
  "unknown"
]);

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

const testTeamEntriesByTeam = new Map<string, TeamEntry[]>();
const defaultTestTeamId = "team_1";

function testEntries(teamId: string): TeamEntry[] {
  const existing = testTeamEntriesByTeam.get(teamId);
  if (existing) return existing;
  const entries = teamId === defaultTestTeamId ? structuredClone(initialTeamEntries) : [];
  testTeamEntriesByTeam.set(teamId, entries);
  return entries;
}

function useTestState(): boolean {
  return process.env.NODE_ENV === "test";
}

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
  if (entry.domains.length === 0) issues.push("at least one domain is required");
  if (!entry.domains.every(nonEmpty)) issues.push("domains are required");
  if (entry.contemporaries && !Array.isArray(entry.contemporaries)) {
    issues.push("contemporaries must be a string array");
  } else if (entry.contemporaries && !entry.contemporaries.every(nonEmpty)) {
    issues.push("contemporaries are required");
  }
  if (entry.sources.length === 0) issues.push("at least one source is required");
  for (const [index, source] of entry.sources.entries()) {
    const issue = validateSource(source);
    if (issue) issues.push(`source ${index}: ${issue}`);
  }
  return issues;
}

function assertValidTeamEntry(entry: TeamEntry): void {
  const issues = validateTeamEntry(entry);
  if (issues.length > 0) throw new Error(`invalid team entry: ${issues.join("; ")}`);
}

function importKey(entry: Pick<TeamEntry, "expansion" | "term">): string {
  return `${entry.term.trim().toLowerCase()}:${entry.expansion.trim().toLowerCase()}`;
}

function normalizeTerm(value: string): string {
  return value.trim().toLowerCase();
}

function entryFromRows(row: EntryRow, sources: SourceRow[]): TeamEntry {
  return {
    contemporaries: row.contemporaries,
    domains: row.domains,
    expansion: row.expansions[0] ?? row.term,
    id: row.id,
    meaning: row.meaning_short,
    sources: sources.map((source) => ({
      license: source.license,
      publisher: source.publisher,
      retrieved_at: source.retrieved_at.toISOString(),
      snippet: source.snippet,
      title: source.title,
      url: source.url
    })),
    term: row.term
  };
}

async function entriesFromRows(rows: EntryRow[]): Promise<TeamEntry[]> {
  if (rows.length === 0) return [];
  const { rows: sourceRows } = await authDb().query<SourceRow>(
    `
    select entry_id, url, title, publisher, license, retrieved_at, snippet
    from team_entry_sources
    where entry_id = any($1::text[])
    order by entry_id, position
    `,
    [rows.map((row) => row.id)]
  );
  const sourcesByEntry = new Map<string, SourceRow[]>();
  for (const source of sourceRows) {
    const sources = sourcesByEntry.get(source.entry_id) ?? [];
    sources.push(source);
    sourcesByEntry.set(source.entry_id, sources);
  }
  return rows.map((row) => entryFromRows(row, sourcesByEntry.get(row.id) ?? []));
}

async function writeSources(client: PoolClient, entryId: string, sources: TeamEntrySource[]) {
  await client.query("delete from team_entry_sources where entry_id = $1", [entryId]);
  for (const [index, source] of sources.entries()) {
    await client.query(
      `
      insert into team_entry_sources (
        id, entry_id, position, url, title, publisher, license, retrieved_at, snippet, source_quality
      ) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'community')
      `,
      [
        randomUUID(),
        entryId,
        index,
        source.url,
        source.title,
        source.publisher,
        source.license,
        new Date(source.retrieved_at),
        source.snippet
      ]
    );
  }
}

export async function getTeamEntries(teamId = defaultTestTeamId): Promise<TeamEntry[]> {
  if (useTestState()) return structuredClone(testEntries(teamId));
  const { rows } = await authDb().query<EntryRow>(
    `
    select id, term, expansions, domains, meaning_short, contemporaries
    from team_entries
    where team_id = $1 and deprecated = false
    order by term_normalized, id
    `,
    [teamId]
  );
  return entriesFromRows(rows);
}

export async function listTeamEntriesPage(
  teamId: string,
  offset: number,
  limit: number
): Promise<{ entries: TeamEntry[]; total: number }> {
  if (useTestState()) {
    const entries = testEntries(teamId);
    return {
      entries: structuredClone(entries.slice(offset, offset + limit)),
      total: entries.length
    };
  }
  const [{ rows }, count] = await Promise.all([
    authDb().query<EntryRow>(
      `
      select id, term, expansions, domains, meaning_short, contemporaries
      from team_entries
      where team_id = $1 and deprecated = false
      order by term_normalized, id
      offset $2 limit $3
      `,
      [teamId, offset, limit]
    ),
    authDb().query<{ count: string }>(
      "select count(*)::text as count from team_entries where team_id = $1 and deprecated = false",
      [teamId]
    )
  ]);
  return {
    entries: await entriesFromRows(rows),
    total: Number(count.rows[0]?.count ?? 0)
  };
}

export function resetTeamEntriesForTest(teamId = defaultTestTeamId): void {
  testTeamEntriesByTeam.set(teamId, structuredClone(initialTeamEntries));
}

export function replaceTeamEntriesForTest(entries: TeamEntry[], teamId = defaultTestTeamId): void {
  testTeamEntriesByTeam.set(teamId, structuredClone(entries));
}

export async function importTeamEntries(
  teamId: string,
  entries: TeamEntry[]
): Promise<{ inserted: TeamEntry[]; skipped: TeamEntry[] }> {
  const existing = new Set((await getTeamEntries(teamId)).map(importKey));
  const inserted: TeamEntry[] = [];
  const skipped: TeamEntry[] = [];
  for (const entry of entries) {
    assertValidTeamEntry(entry);
    const key = importKey(entry);
    if (existing.has(key)) {
      skipped.push(entry);
      continue;
    }
    inserted.push(await createTeamEntry(teamId, entry));
    existing.add(key);
  }
  return { inserted, skipped };
}

export async function createTeamEntry(teamId: string, entry: TeamEntry): Promise<TeamEntry> {
  assertValidTeamEntry(entry);
  if (useTestState()) {
    const entries = testEntries(teamId);
    const key = importKey(entry);
    if (entries.some((item) => importKey(item) === key || item.id === entry.id)) {
      throw new Error("team entry already exists");
    }
    entries.push(structuredClone(entry));
    return structuredClone(entry);
  }

  const client = await authDb().connect();
  try {
    await client.query("begin");
    const { rows } = await client.query<EntryRow>(
      `
      insert into team_entries (
        id, team_id, term, term_normalized, expansions, domains, meaning_short, meaning_long,
        confidence_tier, license, layer, aliases, related_terms, contemporaries
      ) values ($1, $2, $3, $4, $5, $6, $7, $7, 'T4', 'proprietary-team', 'team', ARRAY[]::text[], ARRAY[]::text[], $8)
      returning id, term, expansions, domains, meaning_short, contemporaries
      `,
      [
        entry.id,
        teamId,
        entry.term.trim(),
        normalizeTerm(entry.term),
        [entry.expansion.trim()],
        entry.domains,
        entry.meaning.trim(),
        entry.contemporaries ?? []
      ]
    );
    await writeSources(client, entry.id, entry.sources);
    await client.query("commit");
    return entryFromRows(rows[0]!, entry.sources.map((source) => ({ ...source, entry_id: entry.id, retrieved_at: new Date(source.retrieved_at) })));
  } catch (error) {
    await client.query("rollback");
    if ((error as { code?: string }).code === "23505") throw new Error("team entry already exists");
    throw error;
  } finally {
    client.release();
  }
}

export async function updateTeamEntry(
  teamId: string,
  entryId: string,
  patch: Partial<TeamEntry>
): Promise<TeamEntry> {
  const entries = await getTeamEntries(teamId);
  const existing = entries.find((item) => item.id === entryId);
  if (!existing) throw new Error("team entry not found");
  const next: TeamEntry = {
    ...existing,
    ...patch,
    id: entryId,
    contemporaries: patch.contemporaries ?? existing.contemporaries
  };
  assertValidTeamEntry(next);

  if (useTestState()) {
    const test = testEntries(teamId);
    const index = test.findIndex((item) => item.id === entryId);
    test[index] = structuredClone(next);
    return structuredClone(next);
  }

  const client = await authDb().connect();
  try {
    await client.query("begin");
    const { rows } = await client.query<EntryRow>(
      `
      update team_entries
      set
        term = $3,
        term_normalized = $4,
        expansions = $5,
        domains = $6,
        meaning_short = $7,
        meaning_long = $7,
        contemporaries = $8,
        updated_at = now()
      where team_id = $1 and id = $2 and deprecated = false
      returning id, term, expansions, domains, meaning_short, contemporaries
      `,
      [
        teamId,
        entryId,
        next.term.trim(),
        normalizeTerm(next.term),
        [next.expansion.trim()],
        next.domains,
        next.meaning.trim(),
        next.contemporaries ?? []
      ]
    );
    if (!rows[0]) throw new Error("team entry not found");
    await writeSources(client, entryId, next.sources);
    await client.query("commit");
    return next;
  } catch (error) {
    await client.query("rollback");
    if ((error as { code?: string }).code === "23505") throw new Error("team entry already exists");
    throw error;
  } finally {
    client.release();
  }
}

export async function deleteTeamEntry(teamId: string, entryId: string): Promise<TeamEntry> {
  const existing = (await getTeamEntries(teamId)).find((entry) => entry.id === entryId);
  if (!existing) throw new Error("team entry not found");
  if (useTestState()) {
    const entries = testEntries(teamId);
    const index = entries.findIndex((entry) => entry.id === entryId);
    entries.splice(index, 1);
    return structuredClone(existing);
  }
  await authDb().query("delete from team_entries where team_id = $1 and id = $2", [
    teamId,
    entryId
  ]);
  return existing;
}

function csvCell(value: string): string {
  return `"${value.replaceAll('"', '""')}"`;
}

export function teamEntriesCsv(entries: TeamEntry[]): string {
  const header = [
    "id",
    "term",
    "expansion",
    "meaning",
    "domains",
    "source_url",
    "source_title",
    "source_publisher",
    "source_license",
    "source_retrieved_at",
    "source_snippet"
  ];
  const rows = entries.flatMap((entry) =>
    entry.sources.map((source) =>
      [
        entry.id,
        entry.term,
        entry.expansion,
        entry.meaning,
        entry.domains.join(";"),
        source.url,
        source.title,
        source.publisher,
        source.license,
        source.retrieved_at,
        source.snippet
      ]
        .map(csvCell)
        .join(",")
    )
  );
  return `${header.join(",")}\n${rows.join("\n")}\n`;
}
