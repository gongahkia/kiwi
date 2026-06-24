import { NextResponse, type NextRequest } from "next/server";

import { listAuditLogPage } from "@/lib/audit-log";
import { pageInfo, paginationWindow } from "@/lib/pagination";

export function GET(request: NextRequest) {
  const window = paginationWindow(request.nextUrl.searchParams);
  const page = listAuditLogPage(window.offset, window.limit);
  return NextResponse.json({ audit: page.audit, page: pageInfo(page.total, window) });
}
