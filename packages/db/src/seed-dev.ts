import { readFile } from "node:fs/promises";
import { Client } from "pg";

type ManualSeed = {
  entries: ManualEntry[];
};

type ManualEntry = {
  aliases: string[];
  coiner: string | null;
  confidence_tier: string;
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
  sources: ManualSource[];
  team_id?: string | null;
  term: string;
  term_normalized: string;
  updated_at: string;
  year_coined: number | null;
};

type ManualSource = {
  license: string;
  publisher: string;
  retrieved_at: string;
  snippet: string;
  source_quality: string;
  title: string;
  url: string;
};

const databaseUrl = process.env.WAT_DATABASE_URL ?? process.env.DATABASE_URL;
const connectionString = databaseUrl ?? "postgres://wat:wat@localhost:5432/wat";
const seedUrl = new URL("../../../ingest/seeds/manual.json", import.meta.url);
const seedLimit = 50;

const entriesSql = `
insert into entries (
  id, term, term_normalized, expansions, domains, meaning_short, meaning_long,
  coiner, year_coined, confidence_tier, license, layer, created_at, updated_at,
  deprecated, deprecated_reason, aliases, related_terms
) values (
  $1, $2, $3, $4, $5, $6, $7,
  $8, $9, $10, $11, $12, $13, $14,
  $15, $16, $17, $18
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
  created_at = excluded.created_at,
  updated_at = excluded.updated_at,
  deprecated = excluded.deprecated,
  deprecated_reason = excluded.deprecated_reason,
  aliases = excluded.aliases,
  related_terms = excluded.related_terms
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

async function main(): Promise<void> {
  const seed = JSON.parse(await readFile(seedUrl, "utf8")) as ManualSeed;
  const entries = selectUniqueEntries(seed.entries, seedLimit);
  const entryIds = entries.map((entry) => entry.id);
  const client = new Client({ connectionString });

  await client.connect();
  try {
    await client.query("begin");
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
        entry.created_at,
        entry.updated_at,
        entry.deprecated,
        entry.deprecated_reason,
        entry.aliases,
        entry.related_terms
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
    if (count !== seedLimit) {
      throw new Error(`seeded ${count} entries, expected ${seedLimit}`);
    }

    await client.query("commit");
    console.log(`Seeded ${count} dev entries.`);
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    await client.end();
  }
}

function selectUniqueEntries(entries: ManualEntry[], limit: number): ManualEntry[] {
  const selected: ManualEntry[] = [];
  const seen = new Set<string>();

  for (const entry of entries) {
    const key = `${entry.term_normalized}:${entry.layer}:${entry.team_id ?? ""}`;
    if (seen.has(key)) continue;
    seen.add(key);
    selected.push(entry);
    if (selected.length === limit) return selected;
  }

  throw new Error(`only found ${selected.length} unique manual entries, expected ${limit}`);
}

await main();
