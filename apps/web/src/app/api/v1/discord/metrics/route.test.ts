import { afterEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";

import { incrementDiscordMetric, resetDiscordMetricsForTest } from "@/lib/discord-monitoring";

import { GET } from "./route";

const previousToken = process.env.DISCORD_METRICS_TOKEN;

describe("GET /api/v1/discord/metrics", () => {
  afterEach(() => {
    resetDiscordMetricsForTest();
    if (previousToken === undefined) {
      delete process.env.DISCORD_METRICS_TOKEN;
    } else {
      process.env.DISCORD_METRICS_TOKEN = previousToken;
    }
  });

  it("requires a metrics token", () => {
    process.env.DISCORD_METRICS_TOKEN = "metrics-secret";

    const response = GET(new NextRequest("https://wat.example.com/api/v1/discord/metrics"));

    expect(response.status).toBe(401);
  });

  it("returns Discord counters", async () => {
    process.env.DISCORD_METRICS_TOKEN = "metrics-secret";
    incrementDiscordMetric("discord_search_total", { status: 200 });

    const response = GET(
      new NextRequest("https://wat.example.com/api/v1/discord/metrics", {
        headers: { authorization: "Bearer metrics-secret" }
      })
    );

    expect(response.status).toBe(200);
    expect(await response.text()).toContain('discord_search_total{status="200"} 1');
  });
});
