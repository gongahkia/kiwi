import type { RawEntry, ScraperPlugin } from "../scraper.js";

export type ExtensionSource =
  | {
      kind: "html";
      license: string;
      name: string;
      parser: "postgis" | "postgres";
      publisher: string;
      sourceQuality: "canonical" | "secondary";
      title: string;
      url: string;
    }
  | {
      aliases?: string[];
      contemporaries?: string[];
      expansion: string;
      kind: "pgxn";
      name: string;
      term: string;
      url: string;
    }
  | {
      aliases?: string[];
      contemporaries?: string[];
      expansion: string;
      kind: "readme";
      license: string;
      name: string;
      parser: "citus" | "timescaledb";
      publisher: string;
      sourceQuality: "canonical" | "secondary";
      term: string;
      title: string;
      url: string;
    };

interface PgxnMetadata {
  abstract?: string;
  license?: Record<string, string> | string | string[];
  resources?: {
    homepage?: string;
    repository?: {
      web?: string;
    };
  };
}

const sourceName = "postgresql-extensions";

const extensionSources: ExtensionSource[] = [
  {
    kind: "html",
    license: "PostgreSQL",
    name: "pg_trgm",
    parser: "postgres",
    publisher: "PostgreSQL Documentation",
    sourceQuality: "canonical",
    title: "PostgreSQL extension: pg_trgm",
    url: "https://www.postgresql.org/docs/current/pgtrgm.html"
  },
  {
    kind: "pgxn",
    name: "pgvector",
    term: "pgvector",
    aliases: ["vector"],
    expansion: "pgvector",
    url: "https://api.pgxn.org/dist/vector.json"
  },
  {
    kind: "html",
    license: "CC-BY-SA-3.0",
    name: "PostGIS",
    parser: "postgis",
    publisher: "PostGIS Project",
    sourceQuality: "canonical",
    title: "PostGIS extension: PostGIS",
    url: "https://postgis.net/docs/manual-dev/postgis_introduction.html"
  },
  {
    kind: "readme",
    license: "Apache-2.0",
    name: "TimescaleDB",
    parser: "timescaledb",
    publisher: "TimescaleDB contributors",
    sourceQuality: "canonical",
    term: "TimescaleDB",
    aliases: ["timescaledb"],
    contemporaries: ["Citus"],
    expansion: "TimescaleDB",
    title: "TimescaleDB README",
    url: "https://raw.githubusercontent.com/timescale/timescaledb/main/README.md"
  },
  {
    kind: "pgxn",
    name: "pg_partman",
    term: "pg_partman",
    aliases: ["PostgreSQL Partition Manager"],
    expansion: "pg_partman",
    url: "https://api.pgxn.org/dist/pg_partman.json"
  },
  {
    kind: "html",
    license: "PostgreSQL",
    name: "pg_stat_statements",
    parser: "postgres",
    publisher: "PostgreSQL Documentation",
    sourceQuality: "canonical",
    title: "PostgreSQL extension: pg_stat_statements",
    url: "https://www.postgresql.org/docs/current/pgstatstatements.html"
  },
  {
    kind: "readme",
    license: "AGPL-3.0-only",
    name: "Citus",
    parser: "citus",
    publisher: "Citus Data",
    sourceQuality: "canonical",
    term: "Citus",
    aliases: ["citus"],
    contemporaries: ["TimescaleDB"],
    expansion: "Citus",
    title: "Citus README",
    url: "https://raw.githubusercontent.com/citusdata/citus/main/README.md"
  }
];

export const postgresqlExtensionsScraper: ScraperPlugin = {
  name: sourceName,
  license: "PostgreSQL",
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();

    for (const source of extensionSources) {
      const entry = await sourceToRawEntry(source, retrievedAt);
      if (entry) yield entry;
    }
  }
};

export async function sourceToRawEntry(
  source: ExtensionSource,
  retrievedAt: string
): Promise<RawEntry | null> {
  if (source.kind === "pgxn") {
    return pgxnMetadataToRawEntry(source, await fetchJson<PgxnMetadata>(source.url), retrievedAt);
  }

  const text = await fetchText(source.url);
  if (source.kind === "readme") return readmeToRawEntry(source, text, retrievedAt);
  return htmlToRawEntry(source, text, retrievedAt);
}

export function pgxnMetadataToRawEntry(
  source: Extract<ExtensionSource, { kind: "pgxn" }>,
  metadata: PgxnMetadata,
  retrievedAt: string
): RawEntry | null {
  const meaning = cleanText(metadata.abstract ?? "");
  const license = pgxnLicense(metadata.license);
  if (!meaning) return null;

  return extensionEntry({
    aliases: source.aliases ?? [],
    contemporaries: source.contemporaries ?? [],
    expansion: source.expansion,
    license,
    meaning,
    publisher: "PostgreSQL Extension Network",
    retrievedAt,
    sourceQuality: "canonical",
    term: source.term,
    title: `PGXN extension: ${source.term}`,
    url: metadata.resources?.repository?.web ?? metadata.resources?.homepage ?? pgxnDistUrl(source)
  });
}

function pgxnLicense(license: PgxnMetadata["license"]): string {
  if (typeof license === "string") return normalizeLicenseId(license);
  if (Array.isArray(license)) return normalizeLicenseId(license[0] ?? "PostgreSQL");
  return normalizeLicenseId(Object.keys(license ?? {})[0] ?? "PostgreSQL");
}

function normalizeLicenseId(license: string): string {
  return license.toLowerCase() === "postgresql" ? "PostgreSQL" : license;
}

export function htmlToRawEntry(
  source: Extract<ExtensionSource, { kind: "html" }>,
  html: string,
  retrievedAt: string
): RawEntry | null {
  const meaning =
    source.parser === "postgis" ? firstPostgisParagraph(html) : firstPostgresModuleParagraph(html);
  if (!meaning) return null;

  return extensionEntry({
    expansion: source.name,
    license: source.license,
    meaning,
    publisher: source.publisher,
    retrievedAt,
    sourceQuality: source.sourceQuality,
    term: source.name,
    title: source.title,
    url: source.url
  });
}

export function readmeToRawEntry(
  source: Extract<ExtensionSource, { kind: "readme" }>,
  markdown: string,
  retrievedAt: string
): RawEntry | null {
  const meaning =
    source.parser === "timescaledb"
      ? timescaleReadmeMeaning(markdown)
      : citusReadmeMeaning(markdown);
  if (!meaning) return null;

  return extensionEntry({
    aliases: source.aliases ?? [],
    contemporaries: source.contemporaries ?? [],
    expansion: source.expansion,
    license: source.license,
    meaning,
    publisher: source.publisher,
    retrievedAt,
    sourceQuality: source.sourceQuality,
    term: source.term,
    title: source.title,
    url: source.url
  });
}

async function fetchText(url: string): Promise<string> {
  const response = await fetch(url, {
    headers: { "user-agent": "wat-ingest/0.0 (https://github.com/wat/wat)" }
  });
  if (!response.ok) throw new Error(`failed to fetch ${url}: ${response.status}`);
  return response.text();
}

async function fetchJson<T>(url: string): Promise<T> {
  return JSON.parse(await fetchText(url)) as T;
}

function extensionEntry({
  aliases = [],
  contemporaries = [],
  expansion,
  license,
  meaning,
  publisher,
  retrievedAt,
  sourceQuality,
  term,
  title,
  url
}: {
  aliases?: string[];
  contemporaries?: string[];
  expansion: string;
  license: string;
  meaning: string;
  publisher: string;
  retrievedAt: string;
  sourceQuality: "canonical" | "secondary";
  term: string;
  title: string;
  url: string;
}): RawEntry {
  return {
    aliases,
    contemporaries,
    domains: ["postgresql", "database", "postgres extension"],
    expansion,
    meaning,
    sources: [
      {
        license,
        publisher,
        retrieved_at: retrievedAt,
        snippet: meaning,
        source_quality: sourceQuality,
        title,
        url
      }
    ],
    term
  };
}

function firstPostgresModuleParagraph(html: string): string {
  const paragraphs = Array.from(html.matchAll(/<p>([\s\S]*?)<\/p>/g), (match) =>
    cleanHtml(match[1] ?? "")
  );
  return paragraphs.find((paragraph) => /\bmodule provides\b/i.test(paragraph)) ?? "";
}

function firstPostgisParagraph(html: string): string {
  const paragraphs = Array.from(html.matchAll(/<p>([\s\S]*?)<\/p>/g), (match) =>
    cleanHtml(match[1] ?? "")
  );
  return paragraphs.find((paragraph) => /^PostGIS is\b/i.test(paragraph)) ?? "";
}

function timescaleReadmeMeaning(markdown: string): string {
  const match = markdown.match(/<h3>(TimescaleDB is [\s\S]*?)<\/h3>/i);
  return cleanMarkdown(match?.[1] ?? "");
}

function citusReadmeMeaning(markdown: string): string {
  const section = markdown.split("## What is Citus?")[1]?.split(/\n##\s+/)[0] ?? "";
  return (
    section
      .split(/\n\s*\n/)
      .map(cleanMarkdown)
      .find((paragraph) => /^Citus is\b/i.test(paragraph)) ?? ""
  );
}

function pgxnDistUrl(source: Extract<ExtensionSource, { kind: "pgxn" }>): string {
  return source.url.replace("https://api.pgxn.org/dist/", "https://pgxn.org/dist/");
}

function cleanHtml(input: string): string {
  return cleanText(
    input
      .replace(/<a[^>]*><\/a>/g, "")
      .replace(/<code[^>]*>([\s\S]*?)<\/code>/g, "$1")
      .replace(/<[^>]+>/g, " ")
      .replace(/&nbsp;/g, " ")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&#39;/g, "'")
      .replace(/&quot;/g, '"')
  );
}

function cleanMarkdown(input: string): string {
  return cleanText(
    input
      .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
      .replace(/<[^>]+>/g, " ")
      .replace(/[*_`]/g, "")
  );
}

function cleanText(input: string): string {
  return input
    .replace(/\s+/g, " ")
    .replace(/\s+([,.;:])/g, "$1")
    .trim();
}
