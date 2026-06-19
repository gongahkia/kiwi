import { NextResponse, type NextRequest } from "next/server";

import { personalEntriesCsv } from "@/lib/personal-entries";

const sessionCookie = "wat_session";

export function GET(request: NextRequest) {
  const userId = request.cookies.get(sessionCookie)?.value.trim();
  if (!userId) {
    return NextResponse.json({ error: "login required" }, { status: 401 });
  }

  return new NextResponse(personalEntriesCsv(userId), {
    headers: {
      "content-disposition": 'attachment; filename="wat-personal-entries.csv"',
      "content-type": "text/csv; charset=utf-8"
    }
  });
}
