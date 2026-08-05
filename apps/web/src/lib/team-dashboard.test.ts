import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { recordSearchEvent, resetSearchAnalyticsForTest } from "@/lib/search-analytics";
import { resetSuggestedEditsForTest, submitNewEntrySuggestion } from "@/lib/suggestions";
import { resetTeamEntriesForTest, updateTeamEntry } from "@/lib/team-entries";
import { getTeamDashboardSnapshot } from "./team-dashboard";

describe("team dashboard", () => {
  beforeEach(() => {
    resetSearchAnalyticsForTest();
    resetSuggestedEditsForTest();
    resetTeamEntriesForTest();
  });

  afterEach(() => {
    resetSearchAnalyticsForTest();
    resetSuggestedEditsForTest();
    resetTeamEntriesForTest();
  });

  it("includes privacy-safe search analytics and glossary health", async () => {
    await recordSearchEvent({
      confidenceDistribution: { T4: 1 },
      latencyMs: 42,
      layerHits: ["team"],
      noResult: false,
      queryHash: "hash_rto",
      resultCount: 1,
      resultTerms: ["RTO"],
      teamId: "team_1"
    });
    await recordSearchEvent({
      confidenceDistribution: {},
      latencyMs: 50,
      layerHits: [],
      noResult: true,
      queryHash: "hash_gap",
      resultCount: 0,
      teamId: "team_1"
    });
    await submitNewEntrySuggestion("team_1", "user_platform", {
      domains: ["ops"],
      expansion: "Recovery Time Objective",
      meaning: "Restore target.",
      source_url: "https://example.com/rto",
      term: "RTO"
    });
    await updateTeamEntry("team_1", "team-example-cap", { review_status: "stale" });

    await expect(getTeamDashboardSnapshot("team_1")).resolves.toMatchObject({
      glossary: {
        noResultGaps: ["hash_gap"],
        pendingSuggestions: 1,
        sourceCoverageRate: 1,
        staleEntries: 1,
        topTerms: [{ count: 1, term: "RTO" }]
      },
      searchAnalytics: {
        confidenceDistribution: { T4: 1 },
        layerHits: { team: 1 },
        p95LatencyMs: 50,
        recentNoResultHashes: ["hash_gap"],
        recentQueryHashes: ["hash_gap", "hash_rto"],
        total: 2
      }
    });
  });
});
