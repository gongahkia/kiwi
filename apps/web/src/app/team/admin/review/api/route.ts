import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { sendSuggestionOutcomeEmail } from "@/lib/email-notifications";
import { pageInfo, paginationWindow } from "@/lib/pagination";
import { approveSuggestion } from "@/lib/suggestion-approval";
import {
  listSuggestedEditsPage,
  reviewSuggestedEdit,
  type SuggestedEditStatus
} from "@/lib/suggestions";

const sessionCookie = "wat_session";

function isStatus(value: unknown): value is SuggestedEditStatus {
  return value === "approved" || value === "pending" || value === "rejected";
}

export function GET(request: NextRequest) {
  const window = paginationWindow(request.nextUrl.searchParams);
  const page = listSuggestedEditsPage(window.offset, window.limit);
  return NextResponse.json({ page: pageInfo(page.total, window), suggestions: page.suggestions });
}

export async function PATCH(request: NextRequest) {
  const body = (await request.json()) as {
    after_jsonb?: unknown;
    id?: unknown;
    status?: unknown;
  };
  if (typeof body.id !== "string" || !isStatus(body.status)) {
    return apiErrorResponse(request, "invalid_review", 400, { message: "invalid review" });
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
    return apiErrorResponse(request, "suggestion_not_found", 404, {
      message: error instanceof Error ? error.message : "review failed"
    });
  }
}
