import { randomUUID } from "node:crypto";

import { authDb } from "@/lib/auth-db";

export interface SearchAnalyticsEvent {
  actorId?: string | null;
  confidenceDistribution: Record<string, number>;
  latencyMs: number;
  layerHits: string[];
  noResult: boolean;
  queryHash: string;
  resultCount: number;
  teamId?: string | null;
}

export interface SearchAnalyticsSummary {
  confidenceDistribution: Record<string, number>;
  layerHits: Record<string, number>;
  noResultCount: number;
  noResultRate: number;
  p95LatencyMs: number;
  recentQueryHashes: string[];
  total: number;
}

interface SearchEventRow {
  confidence_distribution: Record<string, number>;
  created_at: Date;
  latency_ms: number;
  layer_hits: string[];
  no_result: boolean;
  query_hash: string;
  result_count: number;
}

const testSearchEvents: SearchAnalyticsEvent[] = [];

function useTestState(): boolean {
  return process.env.NODE_ENV === "test";
}

function normalizeCounts(value: Record<string, number>): Record<string, number> {
  return Object.fromEntries(
    Object.entries(value).filter(([, count]) => Number.isFinite(count) && count > 0)
  );
}

function normalizeEvent(event: SearchAnalyticsEvent): SearchAnalyticsEvent {
  return {
    actorId: event.actorId ?? null,
    confidenceDistribution: normalizeCounts(event.confidenceDistribution),
    latencyMs: Math.max(0, Math.round(event.latencyMs)),
    layerHits: Array.from(new Set(event.layerHits.filter(Boolean))).sort(),
    noResult: event.noResult,
    queryHash: event.queryHash,
    resultCount: Math.max(0, Math.round(event.resultCount)),
    teamId: event.teamId ?? null
  };
}

export async function recordSearchEvent(event: SearchAnalyticsEvent): Promise<void> {
  const normalized = normalizeEvent(event);
  if (useTestState()) {
    testSearchEvents.unshift(structuredClone(normalized));
    return;
  }

  await authDb().query(
    `
    insert into search_events (
      id, team_id, actor_id, query_hash, layer_hits, confidence_distribution,
      result_count, no_result, latency_ms
    ) values ($1, $2, $3, $4, $5, $6::jsonb, $7, $8, $9)
    `,
    [
      randomUUID(),
      normalized.teamId,
      normalized.actorId,
      normalized.queryHash,
      normalized.layerHits,
      JSON.stringify(normalized.confidenceDistribution),
      normalized.resultCount,
      normalized.noResult,
      normalized.latencyMs
    ]
  );
}

export async function getSearchAnalyticsSummary(teamId: string): Promise<SearchAnalyticsSummary> {
  const events = useTestState()
    ? testSearchEvents.filter((event) => event.teamId === teamId)
    : await loadRecentSearchEvents(teamId);

  return summarizeSearchEvents(events);
}

async function loadRecentSearchEvents(teamId: string): Promise<SearchAnalyticsEvent[]> {
  const { rows } = await authDb().query<SearchEventRow>(
    `
    select query_hash, layer_hits, confidence_distribution, result_count, no_result, latency_ms, created_at
    from search_events
    where team_id = $1
    order by created_at desc
    limit 500
    `,
    [teamId]
  );

  return rows.map((row) => ({
    confidenceDistribution: row.confidence_distribution,
    latencyMs: row.latency_ms,
    layerHits: row.layer_hits,
    noResult: row.no_result,
    queryHash: row.query_hash,
    resultCount: row.result_count,
    teamId
  }));
}

function summarizeSearchEvents(events: SearchAnalyticsEvent[]): SearchAnalyticsSummary {
  const confidenceDistribution: Record<string, number> = {};
  const layerHits: Record<string, number> = {};
  const latencies = events.map((event) => event.latencyMs).sort((a, b) => a - b);
  const recentQueryHashes = Array.from(new Set(events.map((event) => event.queryHash))).slice(
    0,
    10
  );

  for (const event of events) {
    for (const layer of event.layerHits) {
      layerHits[layer] = (layerHits[layer] ?? 0) + 1;
    }
    for (const [tier, count] of Object.entries(event.confidenceDistribution)) {
      confidenceDistribution[tier] = (confidenceDistribution[tier] ?? 0) + count;
    }
  }

  const noResultCount = events.filter((event) => event.noResult).length;
  const p95Index = latencies.length === 0 ? -1 : Math.ceil(latencies.length * 0.95) - 1;

  return {
    confidenceDistribution,
    layerHits,
    noResultCount,
    noResultRate: events.length === 0 ? 0 : noResultCount / events.length,
    p95LatencyMs: p95Index < 0 ? 0 : latencies[p95Index]!,
    recentQueryHashes,
    total: events.length
  };
}

export function resetSearchAnalyticsForTest(): void {
  testSearchEvents.length = 0;
}
