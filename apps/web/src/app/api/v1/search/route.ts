import { createHash } from "node:crypto";

import { NextResponse, type NextRequest } from "next/server";
import type { SearchResponse, SearchResult } from "@wat/search";
import { applyDomainContextBoost } from "@wat/search/boost";

import { resolveApiIdentity } from "@/lib/api-identity";
import { checkRateLimit, rateLimitConfigFromEnv } from "@/lib/rate-limit";
import { getPublicEntries, getScopedTeamEntries } from "@/lib/search-data";
import { confidenceRank, scoreEntry, sortMatches } from "@/lib/search-core";

export const runtime = "nodejs";

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
