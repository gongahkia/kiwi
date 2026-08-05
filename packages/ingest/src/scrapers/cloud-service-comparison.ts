import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import type { RawEntry, ScraperPlugin } from "../scraper.js";

export type CloudProvider = "aws" | "azure" | "gcp";

export interface CloudComparisonProduct {
  name: string;
  provider: CloudProvider;
  url?: string;
}

export interface CloudComparisonRow {
  aws: CloudComparisonProduct[];
  azure: CloudComparisonProduct[];
  category: string;
  description: string;
  gcp: CloudComparisonProduct[];
  serviceType: string;
}

export interface ExistingCloudEntry {
  aliases?: string[];
  contemporaries?: string[];
  domains?: string[];
  expansions?: string[];
  meaning_short?: string;
  term: string;
}

interface ProductIdentity {
  aliases: string[];
  domains: string[];
  expansion: string;
  meaning: string;
  term: string;
}

const sourceName = "cloud-service-comparison";
const sourceUrl = "https://docs.cloud.google.com/docs/get-started/aws-azure-gcp-service-comparison";
const sourceFetchUrl = `${sourceUrl}?hl=en`;
const sourceLicense = "CC-BY-4.0";

export const cloudServiceComparisonScraper: ScraperPlugin = {
  name: sourceName,
  license: sourceLicense,
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();
    const [html, existingEntries] = await Promise.all([
      fetchText(sourceFetchUrl),
      loadExistingCloudEntries()
    ]);

    for (const entry of comparisonRowsToRawEntries(
      htmlToComparisonRows(html),
      retrievedAt,
      existingEntries
    )) {
      yield entry;
    }
  }
};

export function htmlToComparisonRows(html: string): CloudComparisonRow[] {
  const table = html.match(/<table\b[^>]*>[\s\S]*?<\/table>/i)?.[0] ?? "";
  return Array.from(table.matchAll(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi)).flatMap((match) => {
    const rowHtml = match[1] ?? "";
    if (/<th\b/i.test(rowHtml)) return [];

    const cells = Array.from(
      rowHtml.matchAll(/<td\b[^>]*>([\s\S]*?)<\/td>/gi),
      (cell) => cell[1] ?? ""
    );
    if (cells.length !== 6) return [];

    const category = cleanHtml(cells[0] ?? "");
    const serviceType = cleanHtml(cells[1] ?? "");
    const description = cleanHtml(cells[3] ?? "");
    const gcpName = cleanHtml(cells[2] ?? "");
    const gcpUrl = firstHref(cells[2] ?? "");
    const aws = splitOfferings(cleanHtml(cells[4] ?? "")).map((name) => product("aws", name));
    const azure = splitOfferings(cleanHtml(cells[5] ?? "")).map((name) => product("azure", name));
    const gcp = gcpName ? [product("gcp", gcpName, gcpUrl)] : [];

    if (gcp.length + aws.length + azure.length < 2) return [];
    return [{ aws, azure, category, description, gcp, serviceType }];
  });
}

export function comparisonRowsToRawEntries(
  rows: CloudComparisonRow[],
  retrievedAt: string,
  existingEntries: ExistingCloudEntry[] = []
): RawEntry[] {
  const existingIndex = buildExistingIndex(existingEntries);
  const entries = new Map<string, RawEntry>();

  for (const row of rows) {
    const products = [...row.gcp, ...row.aws, ...row.azure];
    const identities = products.map((item) => productIdentity(item, row, existingIndex));

    for (let index = 0; index < products.length; index += 1) {
      const product = products[index];
      const identity = identities[index];
      if (!product || !identity) continue;

      const contemporaries = identities
        .filter((candidate) => candidate.term !== identity.term)
        .map((candidate) => candidate.expansion);
      const key = `${identity.term}\u0000${identity.expansion}`;
      const existing = entries.get(key);
      const next = rawEntryForProduct(product, row, identity, contemporaries, retrievedAt);

      entries.set(key, existing ? mergeRawEntries(existing, next) : next);
    }
  }

  return Array.from(entries.values());
}

async function fetchText(url: string): Promise<string> {
  const response = await fetch(url, {
    headers: {
      "accept-language": "en",
      "user-agent": "wat-ingest/0.0 (https://github.com/wat/wat)"
    }
  });
  if (!response.ok) {
    throw new Error(`failed to fetch ${url}: ${response.status}`);
  }
  return response.text();
}

async function loadExistingCloudEntries(): Promise<ExistingCloudEntry[]> {
  const rootDir = fileURLToPath(new URL("../../../..", import.meta.url));
  const deltasDir = join(rootDir, "data", "deltas");
  const entries: ExistingCloudEntry[] = [];

  for (const dateEntry of await readdir(deltasDir, { withFileTypes: true }).catch(() => [])) {
    if (!dateEntry.isDirectory()) continue;
    for (const source of ["aws-services", "azure-services", "gcp-services"]) {
      const path = join(deltasDir, dateEntry.name, `${source}.json`);
      const parsed = await readJsonFile<{ entries?: ExistingCloudEntry[] }>(path);
      entries.push(...(parsed?.entries ?? []));
    }
  }

  return entries;
}

async function readJsonFile<T>(path: string): Promise<T | null> {
  try {
    return JSON.parse(await readFile(path, "utf8")) as T;
  } catch {
    return null;
  }
}

function rawEntryForProduct(
  product: CloudComparisonProduct,
  row: CloudComparisonRow,
  identity: ProductIdentity,
  contemporaries: string[],
  retrievedAt: string
): RawEntry {
  return {
    aliases: identity.aliases,
    contemporaries,
    domains: identity.domains,
    expansion: identity.expansion,
    meaning: identity.meaning,
    sources: [
      {
        license: sourceLicense,
        publisher: "Google Cloud Documentation",
        retrieved_at: retrievedAt,
        snippet: `${row.category} / ${row.serviceType}: ${identity.expansion}`,
        source_quality: "canonical",
        title: "Compare AWS and Azure services to Google Cloud",
        url: sourceUrl
      }
    ],
    term: identity.term
  };
}

function productIdentity(
  product: CloudComparisonProduct,
  row: CloudComparisonRow,
  existingIndex: Map<CloudProvider, Map<string, ExistingCloudEntry>>
): ProductIdentity {
  const existing = matchExisting(product, existingIndex);
  const derived = deriveNameParts(product.name);
  const expansion = existing?.expansions?.[0] ?? derived.expansion;

  return {
    aliases: uniqueStrings([
      ...(existing?.aliases ?? []),
      ...derived.aliases,
      product.name === expansion ? "" : product.name
    ]),
    domains: uniqueStrings([
      ...(existing?.domains ?? []),
      "cloud",
      "cloud service comparison",
      ...providerDomains(product.provider),
      row.category.toLowerCase(),
      row.serviceType.toLowerCase()
    ]),
    expansion,
    meaning:
      existing?.meaning_short ??
      (product.provider === "gcp" && row.description
        ? row.description
        : `${derived.expansion} is mapped by Google Cloud as comparable for ${row.category} / ${row.serviceType}.`),
    term: existing?.term ?? derived.term
  };
}

function buildExistingIndex(
  entries: ExistingCloudEntry[]
): Map<CloudProvider, Map<string, ExistingCloudEntry>> {
  const indexes = new Map<CloudProvider, Map<string, ExistingCloudEntry>>();
  for (const provider of ["aws", "azure", "gcp"] as const) {
    const providerEntries = entries.filter((entry) => entryProvider(entry) === provider);
    const buckets = new Map<string, ExistingCloudEntry[]>();

    for (const entry of providerEntries) {
      for (const key of entryKeys(entry)) {
        buckets.set(key, [...(buckets.get(key) ?? []), entry]);
      }
    }

    indexes.set(
      provider,
      new Map(
        Array.from(buckets)
          .filter(([, matches]) => matches.length === 1)
          .map(([key, matches]) => [key, matches[0]!])
      )
    );
  }
  return indexes;
}

function matchExisting(
  product: CloudComparisonProduct,
  existingIndex: Map<CloudProvider, Map<string, ExistingCloudEntry>>
): ExistingCloudEntry | null {
  const index = existingIndex.get(product.provider);
  if (!index) return null;

  for (const key of productKeys(product)) {
    const entry = index.get(key);
    if (entry) return entry;
  }
  return null;
}

function entryProvider(entry: ExistingCloudEntry): CloudProvider | null {
  const domains = new Set((entry.domains ?? []).map((domain) => domain.toLowerCase()));
  if (domains.has("aws")) return "aws";
  if (domains.has("azure")) return "azure";
  if (domains.has("gcp") || domains.has("google cloud")) return "gcp";
  return null;
}

function entryKeys(entry: ExistingCloudEntry): string[] {
  return uniqueStrings(
    [entry.term, ...(entry.expansions ?? []), ...(entry.aliases ?? [])].flatMap(lookupKeys)
  );
}

function productKeys(product: CloudComparisonProduct): string[] {
  return uniqueStrings([
    ...lookupKeys(product.name),
    ...lookupKeys(product.url?.split("/").filter(Boolean).at(-1) ?? "")
  ]);
}

function lookupKeys(value: string): string[] {
  const clean = cleanServiceName(value);
  const parenthetical = Array.from(clean.matchAll(/\(([^)]+)\)/g), (match) => match[1] ?? "");
  const withoutParenthetical = clean.replace(/\s*\([^)]+\)\s*/g, " ");
  return uniqueStrings(
    [clean, withoutParenthetical, ...parenthetical]
      .flatMap((item) => [item, simplifiedServiceKey(item)])
      .map(normalizeKey)
      .filter(Boolean)
  );
}

function deriveNameParts(name: string): { aliases: string[]; expansion: string; term: string } {
  const clean = cleanServiceName(name);
  const parenthetical = clean.match(/\(([^)]+)\)\s*$/)?.[1] ?? "";
  const expansion = cleanText(clean.replace(/\s*\([^)]+\)\s*$/g, ""));
  const aliases = parenthetical ? [parenthetical, clean] : [];
  const term = /^[A-Z0-9][A-Z0-9+.-]{1,12}$/.test(parenthetical) ? parenthetical : expansion;
  return { aliases, expansion, term };
}

function splitOfferings(value: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let start = 0;

  for (let index = 0; index < value.length; index += 1) {
    const char = value[index];
    if (char === "(") depth += 1;
    if (char === ")") depth = Math.max(0, depth - 1);
    if (char === "," && depth === 0) {
      parts.push(value.slice(start, index));
      start = index + 1;
    }
  }
  parts.push(value.slice(start));

  return parts.map(cleanServiceName).filter(Boolean);
}

function firstHref(html: string): string | undefined {
  const href = html.match(/href="([^"]+)"/i)?.[1];
  if (!href) return undefined;
  return href.startsWith("http") ? href : `https://docs.cloud.google.com${href}`;
}

function product(provider: CloudProvider, name: string, url?: string): CloudComparisonProduct {
  return { name, provider, url };
}

function providerDomains(provider: CloudProvider): string[] {
  if (provider === "aws") return ["aws"];
  if (provider === "azure") return ["azure"];
  return ["gcp", "google cloud"];
}

function mergeRawEntries(left: RawEntry, right: RawEntry): RawEntry {
  return {
    ...left,
    aliases: uniqueStrings([...(left.aliases ?? []), ...(right.aliases ?? [])]),
    contemporaries: uniqueStrings([
      ...(left.contemporaries ?? []),
      ...(right.contemporaries ?? [])
    ]),
    domains: uniqueStrings([...(left.domains ?? []), ...(right.domains ?? [])])
  };
}

function cleanHtml(html: string): string {
  return cleanText(
    decodeHtmlEntities(
      html
        .replace(/<br\s*\/?>/gi, " ")
        .replace(/<[^>]+>/g, " ")
        .replace(/\s+/g, " ")
    )
  );
}

function cleanServiceName(input: string): string {
  return cleanText(input).replace(/\s+,$/, "");
}

function simplifiedServiceKey(input: string): string {
  return input
    .replace(/\b(amazon|aws|microsoft|azure|google cloud|google)\b/gi, " ")
    .replace(/\b(json|admin|management)\s+api\b/gi, " ")
    .replace(/\b(api|client)\b$/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeKey(input: string): string {
  return cleanText(input)
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9+.-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function decodeHtmlEntities(input: string): string {
  return input
    .replace(/&amp;/g, "&")
    .replace(/&nbsp;/g, " ")
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

function cleanText(input: string): string {
  return input.replace(/\s+/g, " ").trim();
}

function uniqueStrings(values: string[]): string[] {
  return Array.from(new Set(values.filter(Boolean)));
}
