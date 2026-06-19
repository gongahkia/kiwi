import { NextResponse } from "next/server";

import { getTeamEntries } from "@/lib/team-entries";

export function GET() {
  return NextResponse.json({
    entries: getTeamEntries(),
    exported_at: new Date().toISOString()
  });
}
