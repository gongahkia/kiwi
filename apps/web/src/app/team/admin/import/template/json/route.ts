import { NextResponse } from "next/server";

import { teamImportJsonTemplate } from "@/lib/team-import-template";

export function GET() {
  return new NextResponse(teamImportJsonTemplate(), {
    headers: {
      "content-disposition": 'attachment; filename="wat-team-import-template.json"',
      "content-type": "application/json; charset=utf-8"
    }
  });
}
