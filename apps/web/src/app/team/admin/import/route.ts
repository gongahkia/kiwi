import { NextResponse, type NextRequest } from "next/server";

import { importTeamEntries, type TeamEntry } from "@/lib/team-entries";

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string" && item.trim());
}

function isTeamEntry(value: unknown): value is TeamEntry {
  if (!value || typeof value !== "object") {
    return false;
  }

  const entry = value as Partial<TeamEntry>;
  return (
    typeof entry.id === "string" &&
    typeof entry.term === "string" &&
    typeof entry.expansion === "string" &&
    typeof entry.meaning === "string" &&
    isStringArray(entry.domains) &&
    Array.isArray(entry.sources) &&
    entry.sources.every(
      (source) =>
        source &&
        typeof source === "object" &&
        typeof source.license === "string" &&
        typeof source.publisher === "string" &&
        typeof source.retrieved_at === "string" &&
        typeof source.snippet === "string" &&
        typeof source.title === "string" &&
        typeof source.url === "string"
    )
  );
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
