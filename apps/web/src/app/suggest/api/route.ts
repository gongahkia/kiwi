import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { checkSuggestionRateLimit } from "@/lib/suggestion-rate-limit";
import { sessionUserFromRequest } from "@/lib/session";
import { submitNewEntrySuggestion, validateSuggestedEntry } from "@/lib/suggestions";

export async function POST(request: NextRequest) {
  const body = (await request.json()) as unknown;
  const input = validateSuggestedEntry(body);
  if (!input) {
    return apiErrorResponse(request, "invalid_suggestion", 400, {
      message: "invalid suggestion"
    });
  }

  const session = await sessionUserFromRequest(request);
  const actorId =
    session?.id ?? request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "anonymous";
  const rateLimit = await checkSuggestionRateLimit(actorId);
  if (!rateLimit.allowed) {
    return apiErrorResponse(request, "rate_limited", 429, {
      fields: { limit: rateLimit.limit, remaining: rateLimit.remaining },
      message: "rate limit exceeded"
    });
  }

  return NextResponse.json({
    suggestion: await submitNewEntrySuggestion(session?.teamId ?? null, session?.id ?? null, input)
  });
}
