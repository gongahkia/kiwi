import { NextResponse, type NextRequest } from "next/server";

import { checkSuggestionRateLimit } from "@/lib/suggestion-rate-limit";
import { submitEntryEditSuggestion, validateSuggestedEntryEdit } from "@/lib/suggestions";

const sessionCookie = "wat_session";

interface SuggestEditRouteContext {
  params: Promise<{ id: string }>;
}

export async function POST(request: NextRequest, context: SuggestEditRouteContext) {
  const actorId = request.cookies.get(sessionCookie)?.value;
  if (!actorId) {
    return NextResponse.json({ error: "login required" }, { status: 401 });
  }
  const rateLimit = checkSuggestionRateLimit(actorId);
  if (!rateLimit.allowed) {
    return NextResponse.json(
      { error: "rate_limited", limit: rateLimit.limit, remaining: rateLimit.remaining },
      { status: 429 }
    );
  }

  const { id } = await context.params;
  const body = (await request.json()) as unknown;
  const input = validateSuggestedEntryEdit(body);
  if (!input) {
    return NextResponse.json({ error: "invalid suggestion" }, { status: 400 });
  }

  return NextResponse.json({
    suggestion: submitEntryEditSuggestion(actorId, id, input)
  });
}
