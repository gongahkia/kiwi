import { NextResponse, type NextRequest } from "next/server";

import { pageInfo, paginationHeaders, paginationWindow } from "@/lib/pagination";
import { listTeamEntriesPage, teamEntriesCsv } from "@/lib/team-entries";

export function GET(request: NextRequest) {
  const window = paginationWindow(request.nextUrl.searchParams);
  const page = listTeamEntriesPage(window.offset, window.limit);
  const headers = paginationHeaders(pageInfo(page.total, window));
  headers.set("content-disposition", 'attachment; filename="wat-team-entries.csv"');
  headers.set("content-type", "text/csv; charset=utf-8");

  return new NextResponse(teamEntriesCsv(page.entries), {
    headers
  });
}
