import { NextResponse, type NextRequest } from "next/server";

import type { SearchEntry } from "@wat/search";

import { apiErrorResponse } from "@/lib/api-error";
import { resolveApiIdentity } from "@/lib/api-identity";
import { getScopedTeamEntries } from "@/lib/search-data";

export const runtime = "nodejs";

function result(entry: SearchEntry) {
  return {
    citations: entry.sources,
    confidence_tier: entry.confidence_tier,
    contemporaries: entry.contemporaries,
    domains: entry.domains,
    entry_id: entry.id,
    expansion: entry.expansions[0] ?? entry.term,
    layer: entry.layer,
    meaning: entry.meaning_short,
    score: 1,
    term: entry.term
  };
}

export async function GET(request: NextRequest) {
  const identity = await resolveApiIdentity(request.headers);
  if (!identity.ok) return apiErrorResponse(request, identity.error, identity.status);
  if (identity.identity.type !== "api" || !identity.identity.teamId) {
    return apiErrorResponse(request, "missing_team_scope", 403, {
      message: "api team scope is required"
    });
  }
  const limit = Number(request.nextUrl.searchParams.get("limit") ?? "25");
  const cursor = Number(request.nextUrl.searchParams.get("cursor") ?? "0");
  const domain = request.nextUrl.searchParams.get("domain")?.trim().toLowerCase();
  const entries = (await getScopedTeamEntries(identity.identity)).filter(
    (entry) => !domain || entry.domains.includes(domain)
  );
  const safeLimit = Number.isFinite(limit) && limit > 0 ? Math.min(limit, 100) : 25;
  const safeCursor = Number.isFinite(cursor) && cursor > 0 ? cursor : 0;
  const page = entries.slice(safeCursor, safeCursor + safeLimit);

  return NextResponse.json({
    entries: page.map(result),
    next_cursor: safeCursor + safeLimit < entries.length ? safeCursor + safeLimit : null,
    team_id: identity.identity.teamId
  });
}
