import { NextRequest, NextResponse } from "next/server";
import type { SearchResponse } from "@wat/search";

import { apiErrorResponse } from "@/lib/api-error";
import { getTeamsInstallByTenantId } from "@/lib/teams-installs";
import { incrementTeamsMetric } from "@/lib/teams-monitoring";

import { GET as searchGET } from "../../search/route";

interface TeamsSearchResult {
  confidence: string;
  domains: string[];
  expansion: string;
  id: string;
  layer: string;
  meaning: string;
  subtitle: string;
  term: string;
  text: string;
  title: string;
  url?: string;
}

interface TeamsSearchResponse {
  results: TeamsSearchResult[];
}

interface TeamsSearchDeps {
  getInstall?: typeof getTeamsInstallByTenantId;
}

export async function getTeamsSearch(request: NextRequest, deps: TeamsSearchDeps = {}) {
  const query =
    request.nextUrl.searchParams.get("q") ?? request.nextUrl.searchParams.get("query") ?? "";
  const headers = new Headers(request.headers);
  const tenantId = teamsTenantId(headers);
  if (tenantId && !headers.get("x-wat-team-id")) {
    const install = await (deps.getInstall ?? getTeamsInstallByTenantId)(tenantId);
    if (!install) {
      incrementTeamsMetric("teams_search_total", { outcome: "unknown_tenant", status: 403 });
      return apiErrorResponse(request, "unknown_teams_tenant", 403, {
        message: "Teams tenant is not mapped to a wat team"
      });
    }
    headers.set("x-wat-team-id", install.team_id);
    if (!headers.get("x-wat-user-id")) headers.set("x-wat-user-id", `teams:${tenantId}`);
  }

  const searchUrl = new URL("/api/v1/search", request.nextUrl.origin);
  searchUrl.searchParams.set("q", query);
  searchUrl.searchParams.set("limit", "5");

  const searchResponse = await searchGET(
    new NextRequest(searchUrl, {
      headers,
      method: "GET"
    })
  );
  if (!searchResponse.ok) {
    incrementTeamsMetric("teams_search_total", {
      outcome: "failed",
      status: searchResponse.status
    });
    return searchResponse;
  }

  const searchBody = (await searchResponse.json()) as SearchResponse;
  const responseHeaders = new Headers(searchResponse.headers);
  responseHeaders.set("content-type", "application/json");
  incrementTeamsMetric("teams_search_total", { outcome: "success", status: 200 });

  return NextResponse.json<TeamsSearchResponse>(
    {
      results: searchBody.matches.map((match) => teamsResult(match.entry, request.nextUrl.origin))
    },
    { headers: responseHeaders, status: 200 }
  );
}

function teamsTenantId(headers: Headers): string | null {
  return headers.get("x-wat-teams-tenant-id")?.trim() || null;
}

function teamsResult(entry: SearchResponse["matches"][number]["entry"], origin: string) {
  const expansion = entry.expansions[0] ?? entry.term;
  const meaning = entry.meaning_short ?? "";
  const result: TeamsSearchResult = {
    confidence: entry.confidence_tier,
    domains: entry.domains,
    expansion,
    id: entry.id,
    layer: entry.layer,
    meaning,
    subtitle: expansion,
    term: entry.term,
    text: meaning,
    title: `${entry.term}: ${expansion}`
  };
  if (entry.id) result.url = new URL(`/term/${encodeURIComponent(entry.id)}`, origin).toString();
  return result;
}
