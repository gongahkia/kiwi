import { NextResponse, type NextRequest } from "next/server";

import type { SearchEntry } from "@wat/search";

import { apiErrorResponse } from "@/lib/api-error";
import { hasApiScope, resolveApiIdentity } from "@/lib/api-identity";
import { getVisibleSearchEntries, resolveContemporaryTerms } from "@/lib/contemporaries";

export const runtime = "nodejs";

function normalizeLookupKey(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^\p{Letter}\p{Number}\s]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

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

function findEntry(term: string, entries: SearchEntry[]): SearchEntry | null {
  const key = normalizeLookupKey(term);
  const matches = entries.filter(
    (entry) =>
      entry.id === term ||
      normalizeLookupKey(entry.term) === key ||
      normalizeLookupKey(entry.term_normalized) === key ||
      entry.aliases.some((alias) => normalizeLookupKey(alias) === key)
  );
  return matches.find((entry) => entry.contemporaries.length > 0) ?? matches[0] ?? null;
}

export async function GET(request: NextRequest) {
  const identity = await resolveApiIdentity(request.headers);
  if (!identity.ok) return apiErrorResponse(request, identity.error, identity.status);
  if (identity.identity.type !== "api" || !identity.identity.teamId) {
    return apiErrorResponse(request, "missing_team_scope", 403, {
      message: "api team scope is required"
    });
  }
  if (!hasApiScope(identity.identity, "search")) {
    return apiErrorResponse(request, "insufficient_api_scope", 403, {
      message: "search scope is required"
    });
  }
  const term = request.nextUrl.searchParams.get("term")?.trim();
  if (!term) {
    return apiErrorResponse(request, "missing_term", 400, { message: "term is required" });
  }
  const entries = await getVisibleSearchEntries(identity.identity);
  const entry = findEntry(term, entries);
  if (!entry) {
    return NextResponse.json({
      alternatives: [],
      entry: null,
      team_id: identity.identity.teamId,
      unresolved_terms: []
    });
  }
  const resolved = resolveContemporaryTerms(entry.contemporaries, entries);
  const byId = new Map(entries.map((candidate) => [candidate.id, candidate]));
  return NextResponse.json({
    alternatives: resolved.flatMap((item) => (item.id ? [result(byId.get(item.id)!)] : [])),
    entry: result(entry),
    team_id: identity.identity.teamId,
    unresolved_terms: resolved.filter((item) => !item.id).map((item) => item.term)
  });
}
