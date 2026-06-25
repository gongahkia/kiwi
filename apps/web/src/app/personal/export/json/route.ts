import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { getPersonalEntries } from "@/lib/personal-entries";
import { sessionUserFromRequest } from "@/lib/session";

export async function GET(request: NextRequest) {
  const session = await sessionUserFromRequest(request);
  if (!session) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }

  return NextResponse.json({
    entries: await getPersonalEntries(session.id),
    exported_at: new Date().toISOString()
  });
}
