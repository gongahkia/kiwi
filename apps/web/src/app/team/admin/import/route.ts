import { NextResponse, type NextRequest } from "next/server";

import { importTeamEntries, type TeamEntry, validateTeamEntry } from "@/lib/team-entries";

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string" && item.trim());
}

function isTeamEntry(value: unknown): value is TeamEntry {
  if (!value || typeof value !== "object") {
    return false;
  }

  const entry = value as Partial<TeamEntry>;
  if (
    !(
      typeof entry.id === "string" &&
      typeof entry.term === "string" &&
      typeof entry.expansion === "string" &&
      typeof entry.meaning === "string" &&
      isStringArray(entry.domains) &&
      Array.isArray(entry.sources)
    )
  ) {
    return false;
  }

  return validateTeamEntry(entry as TeamEntry).length === 0;
}

export async function POST(request: NextRequest) {
  const body = (await request.json()) as { entries?: unknown };
  if (!Array.isArray(body.entries) || !body.entries.every(isTeamEntry)) {
    return NextResponse.json({ error: "invalid team import" }, { status: 400 });
  }

  const result = importTeamEntries(body.entries);

  return NextResponse.json({
    inserted: result.inserted.length,
    skipped: result.skipped.length
  });
}
