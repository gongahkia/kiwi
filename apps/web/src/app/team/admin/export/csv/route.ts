import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { pageInfo, paginationHeaders, paginationWindow } from "@/lib/pagination";
import { sessionUserFromRequest } from "@/lib/session";
import { listTeamEntriesPage, teamEntriesCsv } from "@/lib/team-entries";

export async function GET(request: NextRequest) {
  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  const window = paginationWindow(request.nextUrl.searchParams);
  const page = await listTeamEntriesPage(session.teamId, window.offset, window.limit);
  const headers = paginationHeaders(pageInfo(page.total, window));
  headers.set("content-disposition", 'attachment; filename="wat-team-entries.csv"');
  headers.set("content-type", "text/csv; charset=utf-8");

  return new NextResponse(teamEntriesCsv(page.entries), {
    headers
  });
}
