import { randomUUID } from "node:crypto";
import type { PoolClient } from "pg";

import { authDb } from "@/lib/auth-db";
import type { TeamEntry, TeamEntrySource } from "@/lib/team-entries";
import { validateTeamEntry } from "@/lib/team-entries";

export type PersonalEntry = TeamEntry;

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

const testPersonalEntriesByUser = new Map<string, PersonalEntry[]>();

function useTestState(): boolean {
  return process.env.NODE_ENV === "test";
}

function testEntries(userId: string): PersonalEntry[] {
  const existing = testPersonalEntriesByUser.get(userId);
  if (existing) return existing;
  const entries: PersonalEntry[] = [];
  testPersonalEntriesByUser.set(userId, entries);
  return entries;
}

function assertValidPersonalEntry(entry: PersonalEntry): void {
  const issues = validateTeamEntry(entry);
  if (issues.length > 0) throw new Error(`invalid personal entry: ${issues.join("; ")}`);
}

function importKey(entry: Pick<PersonalEntry, "expansion" | "term">): string {
  return `${entry.term.trim().toLowerCase()}:${entry.expansion.trim().toLowerCase()}`;
}

function normalizeTerm(value: string): string {
  return value.trim().toLowerCase();
}

function entryFromRows(row: EntryRow, sources: SourceRow[]): PersonalEntry {
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

async function entriesFromRows(rows: EntryRow[]): Promise<PersonalEntry[]> {
  if (rows.length === 0) return [];
  const { rows: sourceRows } = await authDb().query<SourceRow>(
    `
    select entry_id, url, title, publisher, license, retrieved_at, snippet
    from personal_entry_sources
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
  await client.query("delete from personal_entry_sources where entry_id = $1", [entryId]);
  for (const [index, source] of sources.entries()) {
    await client.query(
      `
      insert into personal_entry_sources (
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

export function resetPersonalEntriesForTest(): void {
  testPersonalEntriesByUser.clear();
}

export async function getPersonalEntries(userId: string): Promise<PersonalEntry[]> {
  if (useTestState()) return structuredClone(testEntries(userId));
  const { rows } = await authDb().query<EntryRow>(
    `
    select id, term, expansions, domains, meaning_short, contemporaries
    from personal_entries
    where user_id = $1 and deprecated = false
    order by term_normalized, id
    `,
    [userId]
  );
  return entriesFromRows(rows);
}

export async function createPersonalEntry(
  userId: string,
  entry: PersonalEntry
): Promise<PersonalEntry> {
  assertValidPersonalEntry(entry);
  if (useTestState()) {
    const entries = testEntries(userId);
    const key = importKey(entry);
    if (entries.some((item) => importKey(item) === key || item.id === entry.id)) {
      throw new Error("personal entry already exists");
    }
    entries.push(structuredClone(entry));
    return structuredClone(entry);
  }

  const client = await authDb().connect();
  try {
    await client.query("begin");
    await client.query(
      `
      insert into personal_entries (
        id, user_id, term, term_normalized, expansions, domains, meaning_short, meaning_long,
        confidence_tier, license, layer, aliases, related_terms, contemporaries
      ) values ($1, $2, $3, $4, $5, $6, $7, $7, 'T4', 'proprietary-personal', 'personal', ARRAY[]::text[], ARRAY[]::text[], $8)
      `,
      [
        entry.id,
        userId,
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
    return structuredClone(entry);
  } catch (error) {
    await client.query("rollback");
    if ((error as { code?: string }).code === "23505") {
      throw new Error("personal entry already exists", { cause: error });
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function updatePersonalEntry(
  userId: string,
  entryId: string,
  patch: Partial<PersonalEntry>
): Promise<PersonalEntry> {
  const existing = (await getPersonalEntries(userId)).find((item) => item.id === entryId);
  if (!existing) throw new Error("personal entry not found");
  const next: PersonalEntry = {
    ...existing,
    ...patch,
    id: entryId,
    contemporaries: patch.contemporaries ?? existing.contemporaries
  };
  assertValidPersonalEntry(next);

  if (useTestState()) {
    const entries = testEntries(userId);
    const index = entries.findIndex((item) => item.id === entryId);
    entries[index] = structuredClone(next);
    return structuredClone(next);
  }

  const client = await authDb().connect();
  try {
    await client.query("begin");
    const { rowCount } = await client.query(
      `
      update personal_entries
      set
        term = $3,
        term_normalized = $4,
        expansions = $5,
        domains = $6,
        meaning_short = $7,
        meaning_long = $7,
        contemporaries = $8,
        updated_at = now()
      where user_id = $1 and id = $2 and deprecated = false
      `,
      [
        userId,
        entryId,
        next.term.trim(),
        normalizeTerm(next.term),
        [next.expansion.trim()],
        next.domains,
        next.meaning.trim(),
        next.contemporaries ?? []
      ]
    );
    if (rowCount === 0) throw new Error("personal entry not found");
    await writeSources(client, entryId, next.sources);
    await client.query("commit");
    return next;
  } catch (error) {
    await client.query("rollback");
    if ((error as { code?: string }).code === "23505") {
      throw new Error("personal entry already exists", { cause: error });
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function deletePersonalEntry(userId: string, entryId: string): Promise<PersonalEntry> {
  const existing = (await getPersonalEntries(userId)).find((entry) => entry.id === entryId);
  if (!existing) throw new Error("personal entry not found");
  if (useTestState()) {
    const entries = testEntries(userId);
    const index = entries.findIndex((entry) => entry.id === entryId);
    entries.splice(index, 1);
    return structuredClone(existing);
  }
  await authDb().query("delete from personal_entries where user_id = $1 and id = $2", [
    userId,
    entryId
  ]);
  return existing;
}

function csvCell(value: string): string {
  return `"${value.replaceAll('"', '""')}"`;
}

export function personalEntriesCsv(entries: PersonalEntry[]): string {
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
