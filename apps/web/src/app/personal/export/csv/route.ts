import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { getPersonalEntries, personalEntriesCsv } from "@/lib/personal-entries";
import { sessionUserFromRequest } from "@/lib/session";

export async function GET(request: NextRequest) {
  const session = await sessionUserFromRequest(request);
  if (!session) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }

  return new NextResponse(personalEntriesCsv(await getPersonalEntries(session.id)), {
    headers: {
      "content-disposition": 'attachment; filename="wat-personal-entries.csv"',
      "content-type": "text/csv; charset=utf-8"
    }
  });
}
