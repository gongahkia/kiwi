import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { listAuditLogPage } from "@/lib/audit-log";
import { pageInfo, paginationWindow } from "@/lib/pagination";
import { sessionUserFromRequest } from "@/lib/session";

export async function GET(request: NextRequest) {
  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  const window = paginationWindow(request.nextUrl.searchParams);
  const page = await listAuditLogPage(session.teamId, window.offset, window.limit);
  return NextResponse.json({ audit: page.audit, page: pageInfo(page.total, window) });
}
