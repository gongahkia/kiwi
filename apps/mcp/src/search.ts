import { apiHeaders, type WatApiConfig } from "./auth.js";
import type { ConfidenceTier, WatAlternativesResult, WatEntry, WatResult } from "./types.js";

interface SearchResponse {
  matches: Array<{
    entry: WatEntry;
    score: number;
  }>;
  team_id?: string;
}

interface TeamEntriesResponse {
  entries: WatResult[];
  next_cursor: number | null;
  team_id: string;
}

function toResult(entry: WatEntry, score: number): WatResult {
  return {
    citations: entry.sources,
    confidence_tier: entry.confidence_tier,
    contemporaries: entry.contemporaries,
    domains: entry.domains,
    entry_id: entry.id,
    expansion: entry.expansions[0] ?? entry.term,
    layer: entry.layer,
    meaning: entry.meaning_short,
    score,
    term: entry.term
  };
}

async function getJson<T>(config: WatApiConfig, path: string): Promise<T> {
  const response = await fetch(`${config.baseUrl}${path}`, {
    headers: apiHeaders(config)
  });
  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new Error(`wat API ${response.status}: ${body || response.statusText}`);
  }
  return (await response.json()) as T;
}

export async function lookupEntries(input: {
  config: WatApiConfig;
  context?: string;
  limit?: number;
  min_confidence?: ConfidenceTier;
  term: string;
}): Promise<{ matches: WatResult[]; team_id: string }> {
  const url = new URL("/api/v1/search", input.config.baseUrl);
  url.searchParams.set("q", input.term);
  if (input.context) url.searchParams.set("context", input.context);
  if (input.limit) url.searchParams.set("limit", String(input.limit));
  if (input.min_confidence) url.searchParams.set("min_confidence", input.min_confidence);
  const data = await getJson<SearchResponse>(
    input.config,
    `${url.pathname}${url.search}`
  );
  return {
    matches: data.matches.map((match) => toResult(match.entry, match.score)),
    team_id: data.team_id ?? "remote"
  };
}

export async function listAlternatives(input: {
  config: WatApiConfig;
  term: string;
}): Promise<WatAlternativesResult & { team_id: string }> {
  const url = new URL("/api/v1/alternatives", input.config.baseUrl);
  url.searchParams.set("term", input.term);
  return getJson<WatAlternativesResult & { team_id: string }>(
    input.config,
    `${url.pathname}${url.search}`
  );
}

export async function listTeamEntries(input: {
  config: WatApiConfig;
  cursor?: number;
  domain?: string;
  limit?: number;
}): Promise<TeamEntriesResponse> {
  const url = new URL("/api/v1/team/entries", input.config.baseUrl);
  if (input.cursor != null) url.searchParams.set("cursor", String(input.cursor));
  if (input.domain) url.searchParams.set("domain", input.domain);
  if (input.limit) url.searchParams.set("limit", String(input.limit));
  return getJson<TeamEntriesResponse>(input.config, `${url.pathname}${url.search}`);
}

export function resultText(results: WatResult[]): string {
  if (results.length === 0) return "No wat matches.";
  return results
    .map((result) => {
      const citations = result.citations.map((source) => source.url).join(", ");
      const alternatives = result.contemporaries.length
        ? `\nAlternatives: ${result.contemporaries.join(", ")}`
        : "";
      return `${result.term}: ${result.expansion} (${result.confidence_tier}, ${result.layer})\n${result.meaning}${alternatives}\nSources: ${citations}`;
    })
    .join("\n\n");
}
