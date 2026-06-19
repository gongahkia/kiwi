import { NextResponse, type NextRequest } from "next/server";

import { getPersonalEntries } from "@/lib/personal-entries";

const sessionCookie = "wat_session";

export function GET(request: NextRequest) {
  const userId = request.cookies.get(sessionCookie)?.value.trim();
  if (!userId) {
    return NextResponse.json({ error: "login required" }, { status: 401 });
  }

  return NextResponse.json({
    entries: getPersonalEntries(userId),
    exported_at: new Date().toISOString()
  });
}
