import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { recordSearchEvent, resetSearchAnalyticsForTest } from "@/lib/search-analytics";
import { getTeamDashboardSnapshot } from "./team-dashboard";

describe("team dashboard", () => {
  beforeEach(() => {
    resetSearchAnalyticsForTest();
  });

  afterEach(() => {
    resetSearchAnalyticsForTest();
  });

  it("includes privacy-safe search analytics", async () => {
    await recordSearchEvent({
      confidenceDistribution: { T4: 1 },
      latencyMs: 42,
      layerHits: ["team"],
      noResult: false,
      queryHash: "hash_rto",
      resultCount: 1,
      teamId: "team_1"
    });

    await expect(getTeamDashboardSnapshot("team_1")).resolves.toMatchObject({
      searchAnalytics: {
        confidenceDistribution: { T4: 1 },
        layerHits: { team: 1 },
        p95LatencyMs: 42,
        recentQueryHashes: ["hash_rto"],
        total: 1
      }
    });
  });
});
