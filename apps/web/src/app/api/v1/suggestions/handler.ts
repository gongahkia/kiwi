import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { resolveApiIdentity } from "@/lib/api-identity";
import { createDbSuggestion, type DbSuggestion } from "@/lib/db-suggestions";
import { checkSuggestionRateLimit } from "@/lib/suggestion-rate-limit";
import { validateSuggestedEntry } from "@/lib/suggestions";

interface ApiSuggestionDeps {
  createSuggestion?: typeof createDbSuggestion;
}

export async function postApiSuggestion(request: NextRequest, deps: ApiSuggestionDeps = {}) {
  const identity = await resolveApiIdentity(request.headers);
  if (!identity.ok) {
    return apiErrorResponse(request, identity.error, identity.status);
  }
  if (identity.identity.type !== "api") {
    return apiErrorResponse(request, "missing_api_scope", 401, {
      message: "api token is required"
    });
  }
  if (!identity.identity.teamId) {
    return apiErrorResponse(request, "missing_team_scope", 403, {
      message: "x-wat-team-id is required"
    });
  }

  const userId = identity.identity.userId ?? "api";
  const rateLimit = await checkSuggestionRateLimit(`${identity.identity.teamId}:${userId}`);
  if (!rateLimit.allowed) {
    return apiErrorResponse(request, "rate_limited", 429, {
      fields: { limit: rateLimit.limit, remaining: rateLimit.remaining },
      message: "rate limit exceeded"
    });
  }

  const input = validateSuggestedEntry((await request.json()) as unknown);
  if (!input) {
    return apiErrorResponse(request, "invalid_suggestion", 400, {
      message: "invalid suggestion"
    });
  }

  const createSuggestion = deps.createSuggestion ?? createDbSuggestion;
  try {
    const suggestion: DbSuggestion = await createSuggestion({
      actorId: userId,
      suggestion: input,
      teamId: identity.identity.teamId
    });
    return NextResponse.json({ suggestion }, { status: 201 });
  } catch (error) {
    return apiErrorResponse(request, "suggestion_create_failed", 500, {
      message: error instanceof Error ? error.message : "suggestion create failed"
    });
  }
}
