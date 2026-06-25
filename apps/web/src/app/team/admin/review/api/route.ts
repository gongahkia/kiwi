import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { sendSuggestionOutcomeEmail } from "@/lib/email-notifications";
import { pageInfo, paginationWindow } from "@/lib/pagination";
import { sessionUserFromRequest } from "@/lib/session";
import { approveSuggestion } from "@/lib/suggestion-approval";
import {
  listSuggestedEditsPage,
  reviewSuggestedEdit,
  type SuggestedEditStatus
} from "@/lib/suggestions";

function isStatus(value: unknown): value is SuggestedEditStatus {
  return value === "approved" || value === "pending" || value === "rejected";
}

export async function GET(request: NextRequest) {
  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  const window = paginationWindow(request.nextUrl.searchParams);
  const page = await listSuggestedEditsPage(session.teamId, window.offset, window.limit);
  return NextResponse.json({ page: pageInfo(page.total, window), suggestions: page.suggestions });
}

export async function PATCH(request: NextRequest) {
  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  const body = (await request.json()) as {
    after_jsonb?: unknown;
    id?: unknown;
    status?: unknown;
  };
  if (typeof body.id !== "string" || !isStatus(body.status)) {
    return apiErrorResponse(request, "invalid_review", 400, { message: "invalid review" });
  }

  try {
    const suggestion = await reviewSuggestedEdit(
      session.teamId,
      body.id,
      session.id,
      body.status,
      body.after_jsonb
    );
    const approval =
      body.status === "approved" ? await approveSuggestion(session.teamId, suggestion, session.id) : null;
    const notification = await sendSuggestionOutcomeEmail(suggestion, body.status);

    return NextResponse.json({
      approval,
      notification,
      suggestion
    });
  } catch (error) {
    return apiErrorResponse(request, "suggestion_not_found", 404, {
      message: error instanceof Error ? error.message : "review failed"
    });
  }
}
