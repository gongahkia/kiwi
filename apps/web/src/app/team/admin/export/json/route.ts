import { NextResponse, type NextRequest } from "next/server";

import { pageInfo, paginationWindow } from "@/lib/pagination";
import { listTeamEntriesPage } from "@/lib/team-entries";

export function GET(request: NextRequest) {
  const window = paginationWindow(request.nextUrl.searchParams);
  const page = listTeamEntriesPage(window.offset, window.limit);
  return NextResponse.json({
    entries: page.entries,
    exported_at: new Date().toISOString(),
    page: pageInfo(page.total, window)
  });
}
