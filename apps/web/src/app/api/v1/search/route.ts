import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { join } from "node:path";

import { NextResponse, type NextRequest } from "next/server";
import type { SearchEntry, SearchResponse, SearchResult } from "@wat/search";
import { applyDomainContextBoost } from "@wat/search/boost";

import { resolveApiIdentity, type ApiIdentity } from "@/lib/api-identity";
import { checkRateLimit, rateLimitConfigFromEnv } from "@/lib/rate-limit";
import { getTeamEntries, type TeamEntry } from "@/lib/team-entries";
import { getTeamMember } from "@/lib/team-members";

export const runtime = "nodejs";

const confidenceRank = {
  T1: 1,
  T2: 2,
  T3: 3,
  T4: 4
} as const;
const layerRank = {
  personal: 3,
  public: 1,
  team: 2
} as const;

async function readSeedJson(): Promise<string> {
  for (const seedPath of [
    join(process.cwd(), "packages/ingest/seeds/manual.json"),
    join(process.cwd(), "../../packages/ingest/seeds/manual.json")
  ]) {
    try {
      return await readFile(seedPath, "utf8");
    } catch {
      continue;
    }
  }

  throw new Error("manual seed file not found");
}

async function getPublicEntries(): Promise<SearchEntry[]> {
  const parsed = JSON.parse(await readSeedJson()) as { entries: SearchEntry[] };
  return parsed.entries.filter((entry) => entry.layer === "public");
}

function teamEntryToSearchEntry(entry: TeamEntry): SearchEntry {
  return {
    aliases: [],
    confidence_tier: "T4",
    domains: entry.domains,
    expansions: [entry.expansion],
    id: entry.id,
    layer: "team",
    meaning_short: entry.meaning,
    sources: entry.sources.map((source) => ({ ...source, source_quality: "community" })),
    term: entry.term,
    term_normalized: entry.term.trim().toLowerCase()
  };
}

function getScopedTeamEntries(identity: ApiIdentity): SearchEntry[] {
  if (identity.type !== "api") return [];
  const member = identity.userId ? getTeamMember(identity.userId) : null;
  if (!member && !identity.teamId) return [];

  return getTeamEntries().map(teamEntryToSearchEntry);
}

function scoreEntry(query: string, entry: SearchEntry): SearchResult | null {
  const normalized = query.toLowerCase().trim();
  const searchable = [
    entry.term,
    entry.term_normalized,
    ...entry.expansions,
    ...entry.domains,
    ...entry.aliases,
    entry.meaning_short
  ]
    .join(" ")
    .toLowerCase();

  if (!searchable.includes(normalized)) {
    return null;
  }

  const exact = entry.term_normalized === normalized ? 1 : 0;
  const expansion = entry.expansions.some((value) => value.toLowerCase().includes(normalized))
    ? 0.8
    : 0;
  const domain = entry.domains.some((value) => value.toLowerCase().includes(normalized)) ? 0.4 : 0;
  const body = entry.meaning_short.toLowerCase().includes(normalized) ? 0.25 : 0;
  const layer = entry.layer === "personal" ? 0.75 : entry.layer === "team" ? 0.5 : 0;
  const score = exact + expansion + domain + body + layer;

  return {
    entry,
    score,
    score_breakdown: {
      bm25: exact + expansion + body,
      domain,
      layer
    }
  };
}

function sortMatches(results: SearchResult[]): SearchResult[] {
  return [...results].sort(
    (left, right) =>
      right.score - left.score ||
      layerRank[right.entry.layer] - layerRank[left.entry.layer] ||
      left.entry.id.localeCompare(right.entry.id)
  );
}

function hashQuery(query: string): string {
  return createHash("sha256").update(query.trim().toLowerCase()).digest("hex");
}

function logSearchEvent(query: string, startedAt: number, matches: SearchResult[]) {
  const confidenceDistribution = matches.reduce<Record<string, number>>((counts, match) => {
    const tier = match.entry.confidence_tier;
    counts[tier] = (counts[tier] ?? 0) + 1;
    return counts;
  }, {});
  const layerHit = Array.from(new Set(matches.map((match) => match.entry.layer)));

  console.info(
    JSON.stringify({
      confidence_distribution: confidenceDistribution,
      event: "search",
      latency_ms: Math.round(performance.now() - startedAt),
      layer_hit: layerHit,
      query_hash: hashQuery(query)
    })
  );
}

function clientIp(request: NextRequest): string {
  return (
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    request.headers.get("x-real-ip") ||
    "127.0.0.1"
  );
}

function withRateLimitHeaders(response: NextResponse, decision: ReturnType<typeof checkRateLimit>) {
  response.headers.set("retry-after", String(decision.retryAfter));
  response.headers.set("x-ratelimit-limit", String(decision.limit));
  response.headers.set("x-ratelimit-remaining", String(decision.remaining));
  response.headers.set("x-ratelimit-reset", String(Math.ceil(decision.resetAt / 1000)));
  response.headers.set("x-ratelimit-scope", decision.scope);

  return response;
}

export async function GET(request: NextRequest) {
  const startedAt = performance.now();
  const identity = resolveApiIdentity(request.headers);
  if (!identity.ok) {
    return NextResponse.json({ error: identity.error }, { status: identity.status });
  }

  const rateLimit = checkRateLimit(
    { identity: identity.identity, ip: clientIp(request) },
    rateLimitConfigFromEnv()
  );
  if (!rateLimit.allowed) {
    return withRateLimitHeaders(
      NextResponse.json(
        {
          error: "rate_limited",
          retry_after: rateLimit.retryAfter,
          scope: rateLimit.scope
        },
        { status: 429 }
      ),
      rateLimit
    );
  }

  const query =
    request.nextUrl.searchParams.get("q") ?? request.nextUrl.searchParams.get("query") ?? "";
  const context = request.nextUrl.searchParams.get("context") ?? "";
  const limit = Number(request.nextUrl.searchParams.get("limit") ?? "10");
  const minConfidence = request.nextUrl.searchParams.get("min_confidence") as
    | keyof typeof confidenceRank
    | null;

  if (!query.trim()) {
    return NextResponse.json<SearchResponse>({ matches: [], suggest_url: "/suggest?term=" });
  }

  const entries = [...(await getPublicEntries()), ...getScopedTeamEntries(identity.identity)];
  const scoredMatches = entries
    .filter(
      (entry) =>
        !minConfidence || confidenceRank[entry.confidence_tier] <= confidenceRank[minConfidence]
    )
    .map((entry) => scoreEntry(query, entry))
    .filter((result): result is SearchResult => result != null);
  const rankedMatches = context.trim()
    ? sortMatches(applyDomainContextBoost(scoredMatches, { context, query }))
    : sortMatches(scoredMatches);
  const matches = rankedMatches.slice(0, Number.isFinite(limit) && limit > 0 ? limit : 10);

  logSearchEvent(query, startedAt, matches);

  return withRateLimitHeaders(
    NextResponse.json<SearchResponse>({
      matches,
      suggest_url: matches.length === 0 ? `/suggest?term=${encodeURIComponent(query)}` : undefined
    }),
    rateLimit
  );
}
