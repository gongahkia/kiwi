import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { parseTeamImportCsv } from "@/lib/team-import-template";
import { importTeamEntries, type TeamEntry, validateTeamEntry } from "@/lib/team-entries";
import { sessionUserFromRequest } from "@/lib/session";
import { checkWriteRateLimit } from "@/lib/write-rate-limit";

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

async function entriesFromRequest(request: NextRequest): Promise<TeamEntry[] | null> {
  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  try {
    if (contentType.includes("text/csv") || contentType.includes("application/csv")) {
      const entries = parseTeamImportCsv(await request.text());
      return entries && entries.every(isTeamEntry) ? entries : null;
    }

    const body = (await request.json()) as { entries?: unknown };
    return Array.isArray(body.entries) && body.entries.every(isTeamEntry) ? body.entries : null;
  } catch {
    return null;
  }
}

export async function POST(request: NextRequest) {
  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  const writeLimit = await checkWriteRateLimit("team-import", session.id);
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

  const entries = await entriesFromRequest(request);
  if (!entries) {
    return apiErrorResponse(request, "invalid_team_import", 400, {
      message: "invalid team import"
    });
  }

  const result = await importTeamEntries(session.teamId, entries);

  return NextResponse.json({
    inserted: result.inserted.length,
    skipped: result.skipped.length
  });
}
