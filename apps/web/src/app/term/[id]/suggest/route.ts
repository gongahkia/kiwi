import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { checkSuggestionRateLimit } from "@/lib/suggestion-rate-limit";
import { submitEntryEditSuggestion, validateSuggestedEntryEdit } from "@/lib/suggestions";

const sessionCookie = "wat_session";

interface SuggestEditRouteContext {
  params: Promise<{ id: string }>;
}

export async function POST(request: NextRequest, context: SuggestEditRouteContext) {
  const actorId = request.cookies.get(sessionCookie)?.value;
  if (!actorId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  const rateLimit = checkSuggestionRateLimit(actorId);
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
    suggestion: submitEntryEditSuggestion(actorId, id, input)
  });
}
