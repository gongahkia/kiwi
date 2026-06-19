import { NextResponse } from "next/server";

import { teamEntriesCsv } from "@/lib/team-entries";

export function GET() {
  return new NextResponse(teamEntriesCsv(), {
    headers: {
      "content-disposition": 'attachment; filename="wat-team-entries.csv"',
      "content-type": "text/csv; charset=utf-8"
    }
  });
}
