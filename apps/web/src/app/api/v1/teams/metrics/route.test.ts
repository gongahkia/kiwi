import { afterEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";

import { incrementTeamsMetric, resetTeamsMetricsForTest } from "@/lib/teams-monitoring";

import { GET } from "./route";

const previousToken = process.env.TEAMS_METRICS_TOKEN;

describe("GET /api/v1/teams/metrics", () => {
  afterEach(() => {
    resetTeamsMetricsForTest();
    if (previousToken === undefined) {
      delete process.env.TEAMS_METRICS_TOKEN;
    } else {
      process.env.TEAMS_METRICS_TOKEN = previousToken;
    }
  });

  it("requires a metrics token", () => {
    process.env.TEAMS_METRICS_TOKEN = "metrics-secret";

    const response = GET(new NextRequest("https://wat.example.com/api/v1/teams/metrics"));

    expect(response.status).toBe(401);
  });

  it("returns Teams counters", async () => {
    process.env.TEAMS_METRICS_TOKEN = "metrics-secret";
    incrementTeamsMetric("teams_search_total", { status: 200 });

    const response = GET(
      new NextRequest("https://wat.example.com/api/v1/teams/metrics", {
        headers: { authorization: "Bearer metrics-secret" }
      })
    );

    expect(response.status).toBe(200);
    expect(await response.text()).toContain('teams_search_total{status="200"} 1');
  });
});
