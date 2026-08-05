import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { checkSuggestionRateLimit } from "@/lib/suggestion-rate-limit";
import { sessionUserFromRequest } from "@/lib/session";
import { submitEntryEditSuggestion, validateSuggestedEntryEdit } from "@/lib/suggestions";

interface SuggestEditRouteContext {
  params: Promise<{ id: string }>;
}

export async function POST(request: NextRequest, context: SuggestEditRouteContext) {
  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  const rateLimit = await checkSuggestionRateLimit(session.id);
  if (!rateLimit.allowed) {
    return apiErrorResponse(request, "rate_limited", 429, {
      fields: { limit: rateLimit.limit, remaining: rateLimit.remaining },
      message: "rate limit exceeded"
    });
  }

  const { id } = await context.params;
  const body = (await request.json()) as unknown;
  const input = validateSuggestedEntryEdit(body);
  if (!input) {
    return apiErrorResponse(request, "invalid_suggestion", 400, {
      message: "invalid suggestion"
    });
  }

  return NextResponse.json({
    suggestion: await submitEntryEditSuggestion(session.teamId, session.id, id, input)
  });
}
