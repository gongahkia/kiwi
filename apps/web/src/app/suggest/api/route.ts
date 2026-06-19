import { NextResponse, type NextRequest } from "next/server";

import { submitNewEntrySuggestion, validateSuggestedEntry } from "@/lib/suggestions";

const sessionCookie = "wat_session";

export async function POST(request: NextRequest) {
  const body = (await request.json()) as unknown;
  const input = validateSuggestedEntry(body);
  if (!input) {
    return NextResponse.json({ error: "invalid suggestion" }, { status: 400 });
  }

  const actorId = request.cookies.get(sessionCookie)?.value ?? "anonymous";
  return NextResponse.json({ suggestion: submitNewEntrySuggestion(actorId, input) });
}
