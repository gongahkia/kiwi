import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  getSearchAnalyticsSummary,
  recordSearchEvent,
  resetSearchAnalyticsForTest
} from "./search-analytics";

describe("search analytics", () => {
  beforeEach(() => {
    resetSearchAnalyticsForTest();
  });

  afterEach(() => {
    resetSearchAnalyticsForTest();
  });

  it("summarizes privacy-safe team search events", async () => {
    await recordSearchEvent({
      confidenceDistribution: { T2: 1 },
      latencyMs: 20,
      layerHits: ["public", "team"],
      noResult: false,
      queryHash: "hash_api",
      resultCount: 1,
      teamId: "team_1"
    });
    await recordSearchEvent({
      confidenceDistribution: {},
      latencyMs: 80,
      layerHits: [],
      noResult: true,
      queryHash: "hash_unknown",
      resultCount: 0,
      teamId: "team_1"
    });
    await recordSearchEvent({
      confidenceDistribution: { T4: 1 },
      latencyMs: 10,
      layerHits: ["team"],
      noResult: false,
      queryHash: "hash_other",
      resultCount: 1,
      teamId: "team_2"
    });

    await expect(getSearchAnalyticsSummary("team_1")).resolves.toEqual({
      confidenceDistribution: { T2: 1 },
      layerHits: { public: 1, team: 1 },
      noResultCount: 1,
      noResultRate: 0.5,
      p95LatencyMs: 80,
      recentQueryHashes: ["hash_unknown", "hash_api"],
      total: 2
    });
  });
});
