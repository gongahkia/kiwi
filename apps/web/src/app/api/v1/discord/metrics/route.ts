import { NextResponse, type NextRequest } from "next/server";

import { discordPrometheusMetrics, incrementDiscordMetric } from "@/lib/discord-monitoring";

export const runtime = "nodejs";

export function GET(request: NextRequest) {
  if (!metricsAuthorized(request)) {
    incrementDiscordMetric("discord_metrics_request_total", { status: 401 });
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  incrementDiscordMetric("discord_metrics_request_total", { status: 200 });
  return new NextResponse(discordPrometheusMetrics(), {
    headers: { "content-type": "text/plain; charset=utf-8" },
    status: 200
  });
}

function metricsAuthorized(request: NextRequest): boolean {
  const token = process.env.DISCORD_METRICS_TOKEN?.trim();
  if (!token) return false;
  if (request.headers.get("authorization") === `Bearer ${token}`) return true;
  return request.headers.get("x-discord-metrics-token") === token;
}
