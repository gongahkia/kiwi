import { NextResponse, type NextRequest } from "next/server";

import { sendSuggestionOutcomeEmail } from "@/lib/email-notifications";
import { approveSuggestion } from "@/lib/suggestion-approval";
import {
  getSuggestedEdits,
  reviewSuggestedEdit,
  type SuggestedEditStatus
} from "@/lib/suggestions";

const sessionCookie = "wat_session";

function isStatus(value: unknown): value is SuggestedEditStatus {
  return value === "approved" || value === "pending" || value === "rejected";
}

export function GET() {
  return NextResponse.json({ suggestions: getSuggestedEdits() });
}

export async function PATCH(request: NextRequest) {
  const body = (await request.json()) as {
    after_jsonb?: unknown;
    id?: unknown;
    status?: unknown;
  };
  if (typeof body.id !== "string" || !isStatus(body.status)) {
    return NextResponse.json({ error: "invalid review" }, { status: 400 });
  }

  try {
    const reviewerId = request.cookies.get(sessionCookie)?.value ?? "admin";
    const suggestion = reviewSuggestedEdit(body.id, reviewerId, body.status, body.after_jsonb);
    const approval = body.status === "approved" ? approveSuggestion(suggestion, reviewerId) : null;
    const notification = await sendSuggestionOutcomeEmail(suggestion, body.status);

    return NextResponse.json({
      approval,
      notification,
      suggestion
    });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "review failed" },
      { status: 404 }
    );
  }
}
