import { readdir, readFile } from "node:fs/promises";
import { Client } from "pg";

type CorpusFile = {
  entries?: Partial<PublicSeedEntry>[];
  generated_at?: string;
  source?: string;
};

type PublicSeedEntry = {
  aliases: string[];
  coiner: string | null;
  confidence_tier: string;
  contemporaries: string[];
  created_at: string;
  deprecated: boolean;
  deprecated_reason: string | null;
  domains: string[];
  examples: string[];
  expansions: string[];
  id: string;
  layer: string;
  license: string;
  meaning_long: string;
  meaning_short: string;
  related_terms: string[];
  sources: PublicSeedSource[];
  team_id?: string | null;
  term: string;
  term_normalized: string;
  updated_at: string;
  year_coined: number | null;
};

type PublicSeedSource = {
  license: string;
  publisher: string;
  retrieved_at: string;
  snippet: string;
  source_quality: string;
  title: string;
  url: string;
};

type SeedPublicCorpusOptions = {
  limit?: number;
};

type SeedPublicCorpusResult = {
  count: number;
};

const databaseUrl = process.env.WAT_DATABASE_URL ?? process.env.DATABASE_URL;
const connectionString = databaseUrl ?? "postgres://wat:wat@localhost:5432/wat";
const manualCorpusPathCandidates = [
  "../../ingest/seeds/manual.json",
  "../../../ingest/seeds/manual.json"
];
const deltaDirectoryCandidates = ["../../../data/deltas", "../../../../data/deltas"];

const entriesSql = `
insert into entries (
  id, term, term_normalized, expansions, domains, meaning_short, meaning_long,
  coiner, year_coined, confidence_tier, license, layer, team_id, created_at, updated_at,
  deprecated, deprecated_reason, aliases, related_terms, contemporaries
) values (
  $1, $2, $3, $4, $5, $6, $7,
  $8, $9, $10, $11, $12, $13, $14, $15,
  $16, $17, $18, $19, $20
)
on conflict (id) do update set
  term = excluded.term,
  term_normalized = excluded.term_normalized,
  expansions = excluded.expansions,
  domains = excluded.domains,
  meaning_short = excluded.meaning_short,
  meaning_long = excluded.meaning_long,
  coiner = excluded.coiner,
  year_coined = excluded.year_coined,
  confidence_tier = excluded.confidence_tier,
  license = excluded.license,
  layer = excluded.layer,
  team_id = excluded.team_id,
  created_at = excluded.created_at,
  updated_at = excluded.updated_at,
  deprecated = excluded.deprecated,
  deprecated_reason = excluded.deprecated_reason,
  aliases = excluded.aliases,
  related_terms = excluded.related_terms,
  contemporaries = excluded.contemporaries
`;

const sourcesSql = `
insert into sources (
  id, entry_id, position, url, title, publisher, license, retrieved_at, snippet, source_quality
) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
on conflict (id) do update set
  entry_id = excluded.entry_id,
  position = excluded.position,
  url = excluded.url,
  title = excluded.title,
  publisher = excluded.publisher,
  license = excluded.license,
  retrieved_at = excluded.retrieved_at,
  snippet = excluded.snippet,
  source_quality = excluded.source_quality
`;

const examplesSql = `
insert into examples (id, entry_id, position, body)
values ($1, $2, $3, $4)
on conflict (id) do update set
  entry_id = excluded.entry_id,
  position = excluded.position,
  body = excluded.body
`;

export async function seedPublicCorpus(
  client: Client,
  options: SeedPublicCorpusOptions = {}
): Promise<SeedPublicCorpusResult> {
  const entries = selectUniqueEntries(await readPublicCorpusEntries(), options.limit);
  const entryIds = entries.map((entry) => entry.id);

  await client.query("begin");
  try {
    await client.query("delete from sources where entry_id = any($1::text[])", [entryIds]);
    await client.query("delete from examples where entry_id = any($1::text[])", [entryIds]);

    for (const entry of entries) {
      await client.query(entriesSql, [
        entry.id,
        entry.term,
        entry.term_normalized,
        entry.expansions,
        entry.domains,
        entry.meaning_short,
        entry.meaning_long,
        entry.coiner,
        entry.year_coined,
        entry.confidence_tier,
        entry.license,
        entry.layer,
        entry.team_id ?? null,
        entry.created_at,
        entry.updated_at,
        entry.deprecated,
        entry.deprecated_reason,
        entry.aliases,
        entry.related_terms,
        entry.contemporaries
      ]);

      for (const [position, source] of entry.sources.entries()) {
        await client.query(sourcesSql, [
          `${entry.id}:source:${position}`,
          entry.id,
          position,
          source.url,
          source.title,
          source.publisher,
          source.license,
          source.retrieved_at,
          source.snippet,
          source.source_quality
        ]);
      }

      for (const [position, example] of entry.examples.entries()) {
        await client.query(examplesSql, [
          `${entry.id}:example:${position}`,
          entry.id,
          position,
          example
        ]);
      }
    }

    const result = await client.query<{ count: string }>(
      "select count(*)::int as count from entries where id = any($1::text[])",
      [entryIds]
    );
    const count = Number(result.rows[0]?.count ?? 0);
    if (count !== entries.length) {
      throw new Error(`seeded ${count} public entries, expected ${entries.length}`);
    }

    await client.query("commit");
    return { count };
  } catch (error) {
    await client.query("rollback");
    throw error;
  }
}

export async function readPublicCorpusEntries(): Promise<PublicSeedEntry[]> {
  const files = [
    await readCorpusFile(manualCorpusPathCandidates),
    ...(await readLatestReviewedDeltas())
  ];
  const entries = files
    .flatMap((file) =>
      (file.entries ?? []).map((entry) => normalizeEntry(entry, file.generated_at))
    )
    .filter((entry) => entry.layer === "public");
  return overlaySeedContemporaries(entries);
}

export async function readLatestReviewedDeltas(): Promise<CorpusFile[]> {
  const directory = await resolveDeltaDirectory();
  const latestBySource = new Map<string, { date: string; file: CorpusFile; path: string }>();
  const dates = (await readdir(directory, { withFileTypes: true }))
    .filter((entry) => entry.isDirectory() && /^\d{4}-\d{2}-\d{2}$/.test(entry.name))
    .map((entry) => entry.name)
    .sort();

  for (const date of dates) {
    const dateDirectory = new URL(`${date}/`, directory);
    const entries = (await readdir(dateDirectory, { withFileTypes: true }))
      .filter((entry) => entry.isFile() && entry.name.endsWith(".json"))
      .sort((left, right) => left.name.localeCompare(right.name));
    for (const entry of entries) {
      const path = new URL(entry.name, dateDirectory);
      const file = JSON.parse(await readFile(path, "utf8")) as CorpusFile;
      if (!file.source || file.source === "example") continue;
      const previous = latestBySource.get(file.source);
      if (
        !previous ||
        date > previous.date ||
        (date === previous.date && path.href > previous.path)
      ) {
        latestBySource.set(file.source, { date, file, path: path.href });
      }
    }
  }

  return [...latestBySource.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([, value]) => value.file);
}

async function resolveDeltaDirectory(): Promise<URL> {
  for (const relativePath of deltaDirectoryCandidates) {
    const directory = new URL(`${relativePath}/`, import.meta.url);
    try {
      await readdir(directory);
      return directory;
    } catch {
      continue;
    }
  }
  throw new Error(`reviewed delta directory not found: ${deltaDirectoryCandidates.join(", ")}`);
}

async function readCorpusFile(relativePaths: string[]): Promise<CorpusFile> {
  for (const relativePath of relativePaths) {
    try {
      return JSON.parse(
        await readFile(new URL(relativePath, import.meta.url), "utf8")
      ) as CorpusFile;
    } catch {
      continue;
    }
  }

  throw new Error(`corpus file not found: ${relativePaths.join(", ")}`);
}

function normalizeEntry(entry: Partial<PublicSeedEntry>, generatedAt = ""): PublicSeedEntry {
  const term = entry.term ?? "";
  const expansions = entry.expansions?.length ? entry.expansions : [term];
  const meaning = entry.meaning_short ?? expansions[0] ?? term;
  const timestamp =
    generatedAt || entry.created_at || entry.updated_at || "1970-01-01T00:00:00.000Z";

  return {
    aliases: entry.aliases ?? [],
    coiner: entry.coiner ?? null,
    confidence_tier: entry.confidence_tier ?? "T3",
    contemporaries: entry.contemporaries ?? [],
    created_at: entry.created_at ?? timestamp,
    deprecated: entry.deprecated ?? false,
    deprecated_reason: entry.deprecated_reason ?? null,
    domains: entry.domains ?? [],
    examples: entry.examples ?? [],
    expansions,
    id: entry.id ?? term,
    layer: entry.layer ?? "public",
    license: entry.license ?? entry.sources?.[0]?.license ?? "MIT",
    meaning_long: entry.meaning_long ?? meaning,
    meaning_short: meaning,
    related_terms: entry.related_terms ?? [],
    sources: entry.sources ?? [],
    team_id: entry.team_id ?? null,
    term,
    term_normalized: entry.term_normalized ?? term.toLowerCase(),
    updated_at: entry.updated_at ?? timestamp,
    year_coined: entry.year_coined ?? null
  };
}

function overlaySeedContemporaries(entries: PublicSeedEntry[]): PublicSeedEntry[] {
  const output: PublicSeedEntry[] = [];
  const byTerm = new Map<string, PublicSeedEntry>();

  for (const entry of entries) {
    const key = entry.term_normalized || entry.term.toLowerCase();
    const existing = byTerm.get(key);
    if (existing && entry.id.startsWith("contemporaries-seed-")) {
      existing.contemporaries = uniqueStrings([
        ...existing.contemporaries,
        ...entry.contemporaries
      ]);
      existing.aliases = uniqueStrings([...existing.aliases, ...entry.aliases]);
      existing.related_terms = uniqueStrings([...existing.related_terms, ...entry.related_terms]);
      continue;
    }

    output.push(entry);
    byTerm.set(key, entry);
  }

  return output;
}

function selectUniqueEntries(entries: PublicSeedEntry[], limit?: number): PublicSeedEntry[] {
  const selected: PublicSeedEntry[] = [];
  const seen = new Set<string>();

  for (const entry of entries) {
    const key = `${entry.term_normalized}:${entry.layer}:${entry.team_id ?? ""}`;
    if (seen.has(key)) continue;
    seen.add(key);
    selected.push(entry);
    if (limit && selected.length === limit) return selected;
  }

  if (limit && selected.length < limit) {
    throw new Error(`only found ${selected.length} unique public entries, expected ${limit}`);
  }

  return selected;
}

function uniqueStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const output: string[] = [];
  for (const value of values) {
    const normalized = value.trim();
    const key = normalized.toLowerCase();
    if (!normalized || seen.has(key)) continue;
    seen.add(key);
    output.push(normalized);
  }
  return output;
}

async function main(): Promise<void> {
  const client = new Client({ connectionString });
  await client.connect();
  try {
    const result = await seedPublicCorpus(client);
    console.log(`Seeded ${result.count} public entries.`);
  } finally {
    await client.end();
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await main();
}
