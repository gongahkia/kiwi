import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { pageInfo, paginationWindow } from "@/lib/pagination";
import { sessionUserFromRequest } from "@/lib/session";
import { listTeamEntriesPage } from "@/lib/team-entries";

export async function GET(request: NextRequest) {
  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  const window = paginationWindow(request.nextUrl.searchParams);
  const page = await listTeamEntriesPage(session.teamId, window.offset, window.limit);
  return NextResponse.json({
    entries: page.entries,
    exported_at: new Date().toISOString(),
    page: pageInfo(page.total, window)
  });
}
