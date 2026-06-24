import { parse } from "yaml";

import type { RawEntry, ScraperPlugin } from "../scraper.js";

interface LandscapeItem {
  aliases: string[];
  category: string;
  description: string;
  groupKeys: string[];
  homepageUrl: string;
  name: string;
  project: string;
  repoUrl: string;
  subcategory: string;
  tag: string;
}

const sourceName = "cncf-landscape";
const landscapeRawUrl = "https://raw.githubusercontent.com/cncf/landscape/master/landscape.yml";
const landscapeBlobUrl = "https://github.com/cncf/landscape/blob/master/landscape.yml";
const sourceLicense = "Apache-2.0";

export const cncfLandscapeScraper: ScraperPlugin = {
  name: sourceName,
  license: sourceLicense,
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();
    const yaml = await fetchText(landscapeRawUrl);

    for (const entry of yamlToRawEntries(yaml, retrievedAt)) {
      yield entry;
    }
  }
};

export function yamlToRawEntries(yaml: string, retrievedAt: string): RawEntry[] {
  const root = asRecord(parse(yaml));
  const items = landscapeItems(root);
  const peersByGroup = peerGroups(items);

  return items.map((item) => itemToRawEntry(item, peersByGroup, retrievedAt));
}

async function fetchText(url: string): Promise<string> {
  const response = await fetch(url, {
    headers: { "user-agent": "wat-ingest/0.0 (https://github.com/wat/wat)" }
  });
  if (!response.ok) {
    throw new Error(`failed to fetch ${url}: ${response.status}`);
  }
  return response.text();
}

function landscapeItems(root: Record<string, unknown> | null): LandscapeItem[] {
  return asArray(root?.landscape).flatMap((categoryNode) => {
    const categoryRecord = asRecord(categoryNode);
    const category = cleanText(stringValue(categoryRecord?.name));

    return asArray(categoryRecord?.subcategories).flatMap((subcategoryNode) => {
      const subcategoryRecord = asRecord(subcategoryNode);
      const subcategory = cleanText(stringValue(subcategoryRecord?.name));

      return asArray(subcategoryRecord?.items).flatMap((itemNode) => {
        const itemRecord = asRecord(itemNode);
        const name = cleanText(stringValue(itemRecord?.name));
        if (!name) return [];

        const extra = asRecord(itemRecord?.extra);
        const secondPath = stringArray(itemRecord?.second_path);
        const project = cleanText(stringValue(itemRecord?.project));

        return [
          {
            aliases: aliasesFromName(name),
            category,
            description: cleanText(stringValue(itemRecord?.description)),
            groupKeys: groupKeys(category, subcategory, secondPath),
            homepageUrl: cleanText(stringValue(itemRecord?.homepage_url)),
            name,
            project,
            repoUrl: cleanText(stringValue(itemRecord?.repo_url)),
            subcategory,
            tag: cleanText(stringValue(extra?.tag))
          }
        ];
      });
    });
  });
}

function itemToRawEntry(
  item: LandscapeItem,
  peersByGroup: Map<string, string[]>,
  retrievedAt: string
): RawEntry {
  const location = [item.category, item.subcategory].filter(Boolean).join(" / ");
  const meaning =
    item.description ||
    `${item.name} is listed in the CNCF Landscape${location ? ` under ${location}` : ""}.`;

  return {
    aliases: item.aliases,
    contemporaries: contemporariesFor(item, peersByGroup),
    domains: domainsForItem(item),
    expansion: item.name,
    meaning,
    sources: [
      {
        license: sourceLicense,
        publisher: "CNCF Landscape",
        retrieved_at: retrievedAt,
        snippet: meaning,
        source_quality: "canonical",
        title: `CNCF Landscape: ${item.name}`,
        url: landscapeBlobUrl
      }
    ],
    term: item.name
  };
}

function peerGroups(items: LandscapeItem[]): Map<string, string[]> {
  const groups = new Map<string, string[]>();
  for (const item of items) {
    for (const key of item.groupKeys) {
      groups.set(key, uniqueStrings([...(groups.get(key) ?? []), item.name]));
    }
  }
  return groups;
}

function contemporariesFor(item: LandscapeItem, peersByGroup: Map<string, string[]>): string[] {
  return uniqueStrings(
    item.groupKeys
      .flatMap((key) => peersByGroup.get(key) ?? [])
      .filter((name) => name !== item.name)
  );
}

function domainsForItem(item: LandscapeItem): string[] {
  return uniqueStrings(
    [
      "cncf",
      "cloud native",
      "cncf landscape",
      "system",
      item.category.toLowerCase(),
      item.subcategory.toLowerCase(),
      item.project ? `cncf:${item.project.toLowerCase()}` : "",
      item.tag ? `tag:${item.tag.toLowerCase()}` : ""
    ].filter(Boolean)
  );
}

function groupKeys(category: string, subcategory: string, secondPaths: string[]): string[] {
  return uniqueStrings([
    categoryPath(category, subcategory),
    ...secondPaths.map((path) => {
      const [secondCategory = "", ...rest] = path.split("/").map(cleanText);
      return categoryPath(secondCategory, rest.join(" / "));
    })
  ]).filter(Boolean);
}

function categoryPath(category: string, subcategory: string): string {
  return [category, subcategory].filter(Boolean).join(" / ");
}

function aliasesFromName(name: string): string[] {
  const aliases: string[] = [];
  const parenthetical = name.match(/\(([^)]+)\)\s*$/)?.[1];
  if (parenthetical) aliases.push(parenthetical);
  if (/^Apache\s+/i.test(name)) aliases.push(name.replace(/^Apache\s+/i, ""));
  return uniqueStrings(aliases.map(cleanText).filter(Boolean));
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map(stringValue).map(cleanText).filter(Boolean);
}

function cleanText(input: string): string {
  return input
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim();
}

function uniqueStrings(values: string[]): string[] {
  return Array.from(new Set(values));
}
