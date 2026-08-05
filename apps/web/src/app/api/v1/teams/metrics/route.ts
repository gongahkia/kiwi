import { NextResponse, type NextRequest } from "next/server";

import { incrementTeamsMetric, teamsPrometheusMetrics } from "@/lib/teams-monitoring";

export const runtime = "nodejs";

export function GET(request: NextRequest) {
  if (!metricsAuthorized(request)) {
    incrementTeamsMetric("teams_metrics_request_total", { status: 401 });
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  incrementTeamsMetric("teams_metrics_request_total", { status: 200 });
  return new NextResponse(teamsPrometheusMetrics(), {
    headers: { "content-type": "text/plain; charset=utf-8" },
    status: 200
  });
}

function metricsAuthorized(request: NextRequest): boolean {
  const token = process.env.TEAMS_METRICS_TOKEN?.trim();
  if (!token) return false;
  if (request.headers.get("authorization") === `Bearer ${token}`) return true;
  return request.headers.get("x-teams-metrics-token") === token;
}
