import type { TeamEntry } from "./team-entries";

export type PersonalEntry = TeamEntry;

const personalEntriesByUser = new Map<string, PersonalEntry[]>();

function userEntries(userId: string): PersonalEntry[] {
  const existing = personalEntriesByUser.get(userId);
  if (existing) return existing;

  const entries: PersonalEntry[] = [];
  personalEntriesByUser.set(userId, entries);
  return entries;
}

function importKey(entry: PersonalEntry): string {
  return `${entry.term.trim().toLowerCase()}:${entry.expansion.trim().toLowerCase()}`;
}

export function resetPersonalEntriesForTest() {
  personalEntriesByUser.clear();
}

export function getPersonalEntries(userId: string): PersonalEntry[] {
  return structuredClone(userEntries(userId));
}

export function createPersonalEntry(userId: string, entry: PersonalEntry): PersonalEntry {
  const entries = userEntries(userId);
  const key = importKey(entry);
  if (entries.some((item) => importKey(item) === key || item.id === entry.id)) {
    throw new Error("personal entry already exists");
  }

  entries.push(structuredClone(entry));
  return structuredClone(entry);
}

export function updatePersonalEntry(
  userId: string,
  entryId: string,
  patch: Partial<PersonalEntry>
): PersonalEntry {
  const entry = userEntries(userId).find((item) => item.id === entryId);
  if (!entry) {
    throw new Error("personal entry not found");
  }

  if (patch.term?.trim()) entry.term = patch.term.trim();
  if (patch.expansion?.trim()) entry.expansion = patch.expansion.trim();
  if (patch.meaning?.trim()) entry.meaning = patch.meaning.trim();
  if (patch.domains) entry.domains = patch.domains;
  if (patch.sources) entry.sources = patch.sources;

  return structuredClone(entry);
}

export function deletePersonalEntry(userId: string, entryId: string): PersonalEntry {
  const entries = userEntries(userId);
  const index = entries.findIndex((entry) => entry.id === entryId);
  if (index === -1) {
    throw new Error("personal entry not found");
  }

  const [removed] = entries.splice(index, 1);
  if (!removed) {
    throw new Error("personal entry not found");
  }

  return structuredClone(removed);
}

function csvCell(value: string): string {
  return `"${value.replaceAll('"', '""')}"`;
}

export function personalEntriesCsv(userId: string, entries = getPersonalEntries(userId)): string {
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
