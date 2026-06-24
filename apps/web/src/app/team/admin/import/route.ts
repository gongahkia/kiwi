import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { importTeamEntries, type TeamEntry, validateTeamEntry } from "@/lib/team-entries";
import { checkWriteRateLimit } from "@/lib/write-rate-limit";

const sessionCookie = "wat_session";

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
  const actorId =
    request.cookies.get(sessionCookie)?.value ??
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    "anonymous";
  const writeLimit = checkWriteRateLimit("team-import", actorId);
  if (!writeLimit.allowed) {
    return apiErrorResponse(request, "rate_limited", 429, {
      fields: {
        limit: writeLimit.limit,
        remaining: writeLimit.remaining,
        reset_at: writeLimit.reset_at
      },
      message: "rate limit exceeded"
    });
  }

  const body = (await request.json()) as { entries?: unknown };
  if (!Array.isArray(body.entries) || !body.entries.every(isTeamEntry)) {
    return apiErrorResponse(request, "invalid_team_import", 400, {
      message: "invalid team import"
    });
  }

  const result = importTeamEntries(body.entries);

  return NextResponse.json({
    inserted: result.inserted.length,
    skipped: result.skipped.length
  });
}
