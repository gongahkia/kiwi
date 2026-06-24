import { NextResponse } from "next/server";

import { teamImportCsvTemplate } from "@/lib/team-import-template";

export function GET() {
  return new NextResponse(teamImportCsvTemplate(), {
    headers: {
      "content-disposition": 'attachment; filename="wat-team-import-template.csv"',
      "content-type": "text/csv; charset=utf-8"
    }
  });
}
