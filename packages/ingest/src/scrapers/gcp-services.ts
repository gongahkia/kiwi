import type { RawEntry, ScraperPlugin } from "../scraper.js";

type GitTreeResponse = {
  tree?: Array<{ path?: string; type?: string }>;
};

const sourceName = "gcp-services";
const treeUrl =
  "https://api.github.com/repos/googleapis/google-api-nodejs-client/git/trees/main?recursive=1";
const rawBaseUrl = "https://raw.githubusercontent.com/googleapis/google-api-nodejs-client/main";
const blobBaseUrl = "https://github.com/googleapis/google-api-nodejs-client/blob/main";

export const gcpServicesScraper: ScraperPlugin = {
  name: sourceName,
  license: "Apache-2.0",
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();
    const paths = await fetchPreferredApiPaths();
    const sources = await fetchApiSources(paths);

    for (const { path, source } of sources) {
      const entry = sourceToRawEntry(path, source, retrievedAt);
      if (entry) yield entry;
    }
  }
};

export function sourceToRawEntry(
  path: string,
  source: string,
  retrievedAt: string
): RawEntry | null {
  const service = path.match(/^src\/apis\/([^/]+)\//)?.[1] ?? "";
  const doc = firstClassDoc(source);
  if (!service || !doc.title) return null;

  return {
    domains: ["gcp", "google cloud", "service names"],
    expansion: doc.title,
    meaning: doc.description || doc.title,
    sources: [
      {
        license: "Apache-2.0",
        publisher: "Google API Node.js Client",
        retrieved_at: retrievedAt,
        snippet: `${service}: ${doc.title}`,
        source_quality: "canonical",
        title: `Google API client: ${service}`,
        url: `${blobBaseUrl}/${path}`
      }
    ],
    term: service
  };
}

async function fetchPreferredApiPaths(): Promise<string[]> {
  const response = await fetch(treeUrl, {
    headers: { "user-agent": "wat-ingest/0.0 (https://github.com/wat/wat)" }
  });
  if (!response.ok) {
    throw new Error(`failed to fetch ${treeUrl}: ${response.status}`);
  }

  const data = (await response.json()) as GitTreeResponse;
  const byService = new Map<string, string[]>();
  for (const item of data.tree ?? []) {
    if (item.type !== "blob" || !item.path) continue;
    const match = item.path.match(/^src\/apis\/([^/]+)\/(v[^/]+)\.ts$/);
    if (!match) continue;
    const service = match[1] ?? "";
    byService.set(service, [...(byService.get(service) ?? []), item.path]);
  }

  return Array.from(byService.values())
    .map(preferredPath)
    .sort((left, right) => left.localeCompare(right));
}

function preferredPath(paths: string[]): string {
  const sorted = [...paths].sort((left, right) => left.localeCompare(right));
  return (
    sorted.find((path) => /\/v1\.ts$/.test(path)) ??
    sorted.find((path) => !/(alpha|beta)/.test(path)) ??
    sorted[sorted.length - 1] ??
    ""
  );
}

async function fetchApiSources(paths: string[]): Promise<Array<{ path: string; source: string }>> {
  const results: Array<{ path: string; source: string }> = [];
  for (let index = 0; index < paths.length; index += 12) {
    const batch = paths.slice(index, index + 12);
    results.push(
      ...(await Promise.all(
        batch.map(async (path) => ({
          path,
          source: await fetchText(`${rawBaseUrl}/${path}`)
        }))
      ))
    );
  }
  return results;
}

async function fetchText(url: string): Promise<string> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`failed to fetch ${url}: ${response.status}`);
  }
  return response.text();
}

function firstClassDoc(source: string): { description: string; title: string } {
  const raw = source.match(/\/\*\*((?:(?!\*\/)[\s\S])*)\*\/\s*export class /)?.[1] ?? "";
  const lines = raw
    .split("\n")
    .map((line) => line.replace(/^\s*\*\s?/, "").trim())
    .filter((line) => line && !line.startsWith("@"));
  const title = cleanText(lines[0] ?? "");
  const description = cleanText(lines.slice(1).join(" "));
  return { description, title };
}

function cleanText(input: string): string {
  return input.replace(/\s+/g, " ").trim();
}
