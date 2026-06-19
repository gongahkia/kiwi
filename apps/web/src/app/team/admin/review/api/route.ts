import { NextResponse, type NextRequest } from "next/server";

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
    return NextResponse.json({
      suggestion: reviewSuggestedEdit(
        body.id,
        request.cookies.get(sessionCookie)?.value ?? "admin",
        body.status,
        body.after_jsonb
      )
    });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "review failed" },
      { status: 404 }
    );
  }
}
