import { createHash } from "node:crypto";

import { NextResponse, type NextRequest } from "next/server";
import type { SearchResponse, SearchResult } from "@wat/search";
import { applyDomainContextBoost } from "@wat/search/boost";

import { apiErrorResponse } from "@/lib/api-error";
import { resolveApiIdentity } from "@/lib/api-identity";
import { applyCorsHeaders } from "@/lib/cors";
import { checkRateLimit, rateLimitConfigFromEnv } from "@/lib/rate-limit";
import { ensureRequestId, requestIdHeader } from "@/lib/request-id";
import {
  getPublicEntries,
  getScopedPersonalEntries,
  getScopedTeamEntries
} from "@/lib/search-data";
import { confidenceRank, scoreEntry, sortMatches } from "@/lib/search-core";

export const runtime = "nodejs";

function hashQuery(query: string): string {
  return createHash("sha256").update(query.trim().toLowerCase()).digest("hex");
}

function logSearchEvent(
  requestId: string,
  query: string,
  startedAt: number,
  matches: SearchResult[]
) {
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
      query_hash: hashQuery(query),
      request_id: requestId
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

function withCorsHeaders(
  response: NextResponse,
  request: NextRequest,
  requestId = ensureRequestId(request.headers)
) {
  applyCorsHeaders(response, request, { methods: "GET, OPTIONS" });
  response.headers.set(requestIdHeader, requestId);
  return response;
}

function withRateLimitHeaders(
  response: NextResponse,
  request: NextRequest,
  decision: ReturnType<typeof checkRateLimit>,
  requestId = ensureRequestId(request.headers)
) {
  response.headers.set("retry-after", String(decision.retryAfter));
  response.headers.set("x-ratelimit-limit", String(decision.limit));
  response.headers.set("x-ratelimit-remaining", String(decision.remaining));
  response.headers.set("x-ratelimit-reset", String(Math.ceil(decision.resetAt / 1000)));
  response.headers.set("x-ratelimit-scope", decision.scope);

  return withCorsHeaders(response, request, requestId);
}

export function OPTIONS(request: NextRequest) {
  return withCorsHeaders(new NextResponse(null, { status: 204 }), request);
}

export async function GET(request: NextRequest) {
  const requestId = ensureRequestId(request.headers);
  const startedAt = performance.now();
  const identity = resolveApiIdentity(request.headers);
  if (!identity.ok) {
    return withCorsHeaders(
      apiErrorResponse(request, identity.error, identity.status, { requestId }),
      request,
      requestId
    );
  }

  const rateLimit = checkRateLimit(
    { identity: identity.identity, ip: clientIp(request) },
    rateLimitConfigFromEnv()
  );
  if (!rateLimit.allowed) {
    return withRateLimitHeaders(
      apiErrorResponse(request, "rate_limited", 429, {
        fields: {
          retry_after: rateLimit.retryAfter,
          scope: rateLimit.scope
        },
        message: "rate limit exceeded",
        requestId
      }),
      request,
      rateLimit,
      requestId
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
    return withRateLimitHeaders(
      NextResponse.json<SearchResponse>({ matches: [], suggest_url: "/suggest?term=" }),
      request,
      rateLimit,
      requestId
    );
  }

  const entries = [
    ...(await getPublicEntries()),
    ...getScopedTeamEntries(identity.identity),
    ...getScopedPersonalEntries(identity.identity)
  ];
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

  logSearchEvent(requestId, query, startedAt, matches);

  return withRateLimitHeaders(
    NextResponse.json<SearchResponse>({
      matches,
      suggest_url: matches.length === 0 ? `/suggest?term=${encodeURIComponent(query)}` : undefined
    }),
    request,
    rateLimit,
    requestId
  );
}
