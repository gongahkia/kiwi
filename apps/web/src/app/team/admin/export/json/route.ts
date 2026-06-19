import { NextResponse } from "next/server";

import { teamEntries } from "@/lib/team-entries";

export function GET() {
  return NextResponse.json({
    entries: teamEntries,
    exported_at: new Date().toISOString()
  });
}
