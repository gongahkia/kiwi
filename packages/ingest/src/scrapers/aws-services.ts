import type { RawEntry, ScraperPlugin } from "../scraper.js";

type GitTreeResponse = {
  tree?: Array<{ path?: string; type?: string }>;
};

type AwsServiceModel = {
  metadata?: {
    endpointPrefix?: string;
    serviceFullName?: string;
    serviceId?: string;
  };
};

const sourceName = "aws-services";
const treeUrl = "https://api.github.com/repos/aws/aws-sdk-js/git/trees/master?recursive=1";
const rawBaseUrl = "https://raw.githubusercontent.com/aws/aws-sdk-js/master";
const blobBaseUrl = "https://github.com/aws/aws-sdk-js/blob/master";

export const awsServicesScraper: ScraperPlugin = {
  name: sourceName,
  license: "Apache-2.0",
  refresh_interval: "weekly",
  async *fetch() {
    const retrievedAt = new Date().toISOString();
    const paths = await fetchLatestModelPaths();
    const models = await fetchServiceModels(paths);

    for (const { model, path } of models) {
      const entry = modelToRawEntry(path, model, retrievedAt);
      if (entry) yield entry;
    }
  }
};

export function modelToRawEntry(
  path: string,
  model: AwsServiceModel,
  retrievedAt: string
): RawEntry | null {
  const fullName = cleanText(model.metadata?.serviceFullName ?? "");
  const term = cleanText(model.metadata?.serviceId ?? model.metadata?.endpointPrefix ?? "");
  if (!term || !fullName) return null;

  return {
    domains: ["aws", "cloud", "service names"],
    expansion: fullName,
    meaning: fullName,
    sources: [
      {
        license: "Apache-2.0",
        publisher: "AWS SDK for JavaScript",
        retrieved_at: retrievedAt,
        snippet: `${term}: ${fullName}`,
        source_quality: "canonical",
        title: `AWS service model: ${term}`,
        url: `${blobBaseUrl}/${path}`
      }
    ],
    term
  };
}

async function fetchLatestModelPaths(): Promise<string[]> {
  const response = await fetch(treeUrl, {
    headers: { "user-agent": "wat-ingest/0.0 (https://github.com/wat/wat)" }
  });
  if (!response.ok) {
    throw new Error(`failed to fetch ${treeUrl}: ${response.status}`);
  }

  const data = (await response.json()) as GitTreeResponse;
  const latestByService = new Map<string, string>();
  for (const item of data.tree ?? []) {
    if (item.type !== "blob" || !item.path) continue;
    const match = item.path.match(/^apis\/(.+)-\d{4}-\d{2}-\d{2}\.normal\.json$/);
    if (!match) continue;
    latestByService.set(match[1] ?? "", item.path);
  }
  return Array.from(latestByService.values()).sort((left, right) => left.localeCompare(right));
}

async function fetchServiceModels(
  paths: string[]
): Promise<Array<{ model: AwsServiceModel; path: string }>> {
  const results: Array<{ model: AwsServiceModel; path: string }> = [];
  for (let index = 0; index < paths.length; index += 12) {
    const batch = paths.slice(index, index + 12);
    results.push(
      ...(await Promise.all(
        batch.map(async (path) => ({
          model: (await fetchJson(`${rawBaseUrl}/${path}`)) as AwsServiceModel,
          path
        }))
      ))
    );
  }
  return results;
}

async function fetchJson(url: string): Promise<unknown> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`failed to fetch ${url}: ${response.status}`);
  }
  return response.json();
}

function cleanText(input: string): string {
  return input.replace(/\s+/g, " ").trim();
}
