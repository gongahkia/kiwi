import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { checkSuggestionRateLimit } from "@/lib/suggestion-rate-limit";
import { submitNewEntrySuggestion, validateSuggestedEntry } from "@/lib/suggestions";

const sessionCookie = "wat_session";

export async function POST(request: NextRequest) {
  const body = (await request.json()) as unknown;
  const input = validateSuggestedEntry(body);
  if (!input) {
    return apiErrorResponse(request, "invalid_suggestion", 400, {
      message: "invalid suggestion"
    });
  }

  const actorId = request.cookies.get(sessionCookie)?.value ?? "anonymous";
  const rateLimit = checkSuggestionRateLimit(actorId);
  if (!rateLimit.allowed) {
    return apiErrorResponse(request, "rate_limited", 429, {
      fields: { limit: rateLimit.limit, remaining: rateLimit.remaining },
      message: "rate limit exceeded"
    });
  }

  return NextResponse.json({ suggestion: submitNewEntrySuggestion(actorId, input) });
}
