import { NextResponse, type NextRequest } from "next/server";

import { checkSuggestionRateLimit } from "@/lib/suggestion-rate-limit";
import { submitNewEntrySuggestion, validateSuggestedEntry } from "@/lib/suggestions";

const sessionCookie = "wat_session";

export async function POST(request: NextRequest) {
  const body = (await request.json()) as unknown;
  const input = validateSuggestedEntry(body);
  if (!input) {
    return NextResponse.json({ error: "invalid suggestion" }, { status: 400 });
  }

  const actorId = request.cookies.get(sessionCookie)?.value ?? "anonymous";
  const rateLimit = checkSuggestionRateLimit(actorId);
  if (!rateLimit.allowed) {
    return NextResponse.json(
      { error: "rate_limited", limit: rateLimit.limit, remaining: rateLimit.remaining },
      { status: 429 }
    );
  }

  return NextResponse.json({ suggestion: submitNewEntrySuggestion(actorId, input) });
}
