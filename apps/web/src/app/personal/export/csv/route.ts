import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { personalEntriesCsv } from "@/lib/personal-entries";

const sessionCookie = "wat_session";

export function GET(request: NextRequest) {
  const userId = request.cookies.get(sessionCookie)?.value.trim();
  if (!userId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }

  return new NextResponse(personalEntriesCsv(userId), {
    headers: {
      "content-disposition": 'attachment; filename="wat-personal-entries.csv"',
      "content-type": "text/csv; charset=utf-8"
    }
  });
}
