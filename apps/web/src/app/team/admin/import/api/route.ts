import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { hasApiScope, resolveApiIdentity } from "@/lib/api-identity";
import { parseTeamImportCsv } from "@/lib/team-import-template";
import { importTeamEntries, type TeamEntry, validateTeamEntry } from "@/lib/team-entries";
import { sessionUserFromRequest } from "@/lib/session";
import { checkWriteRateLimit } from "@/lib/write-rate-limit";

interface ImportActor {
  actorId: string;
  teamId: string;
}

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

async function importActorFromRequest(
  request: NextRequest
): Promise<{ actor: ImportActor } | { error: NextResponse }> {
  const identity = await resolveApiIdentity(request.headers);
  if (!identity.ok) {
    return { error: apiErrorResponse(request, identity.error, identity.status) };
  }

  if (identity.identity.type === "api") {
    if (!identity.identity.teamId) {
      return {
        error: apiErrorResponse(request, "missing_team_scope", 403, {
          message: "team-scoped API key is required"
        })
      };
    }
    if (!hasApiScope(identity.identity, "admin")) {
      return {
        error: apiErrorResponse(request, "insufficient_api_scope", 403, {
          message: "admin scope is required"
        })
      };
    }

    return {
      actor: {
        actorId: identity.identity.userId ?? identity.identity.tokenId ?? "api",
        teamId: identity.identity.teamId
      }
    };
  }

  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return {
      error: apiErrorResponse(request, "login_required", 401, { message: "login required" })
    };
  }
  if (session.role !== "admin") {
    return {
      error: apiErrorResponse(request, "admin_required", 403, { message: "admin required" })
    };
  }

  return { actor: { actorId: session.id, teamId: session.teamId } };
}

export async function POST(request: NextRequest) {
  const auth = await importActorFromRequest(request);
  if ("error" in auth) return auth.error;

  const writeLimit = await checkWriteRateLimit("team-import", auth.actor.actorId);
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

  const result = await importTeamEntries(auth.actor.teamId, entries);

  return NextResponse.json({
    inserted: result.inserted.length,
    skipped: result.skipped.length
  });
}
