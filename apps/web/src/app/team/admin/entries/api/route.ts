import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { recordAuditLog } from "@/lib/audit-log";
import { pageInfo, paginationWindow } from "@/lib/pagination";
import { sessionUserFromRequest, type WatSessionUser } from "@/lib/session";
import {
  createTeamEntry,
  deleteTeamEntry,
  getTeamEntries,
  listTeamEntriesPage,
  updateTeamEntry,
  type TeamEntry,
  validateTeamEntry
} from "@/lib/team-entries";

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string" && item.trim());
}

function isTeamEntry(value: unknown): value is TeamEntry {
  if (!value || typeof value !== "object") return false;
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

async function requireAdmin(request: NextRequest) {
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
  return { session: session as WatSessionUser & { teamId: string } };
}

export async function GET(request: NextRequest) {
  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  const window = paginationWindow(request.nextUrl.searchParams);
  const page = await listTeamEntriesPage(session.teamId, window.offset, window.limit);
  return NextResponse.json({ entries: page.entries, page: pageInfo(page.total, window) });
}

export async function POST(request: NextRequest) {
  const auth = await requireAdmin(request);
  if ("error" in auth) return auth.error;
  const body = (await request.json()) as unknown;
  if (!isTeamEntry(body)) {
    return apiErrorResponse(request, "invalid_team_entry", 400, {
      message: "invalid team entry"
    });
  }

  try {
    const entry = await createTeamEntry(auth.session.teamId, body);
    await recordAuditLog({
      action: "team_entry.create",
      actor_id: auth.session.id,
      after_jsonb: entry,
      before_jsonb: null,
      target_id: entry.id,
      target_type: "team_entry",
      team_id: auth.session.teamId
    });
    return NextResponse.json({ entry });
  } catch (error) {
    return apiErrorResponse(request, "team_entry_conflict", 409, {
      message: error instanceof Error ? error.message : "create failed"
    });
  }
}

export async function PATCH(request: NextRequest) {
  const auth = await requireAdmin(request);
  if ("error" in auth) return auth.error;
  const body = (await request.json()) as { id?: unknown; patch?: unknown };
  if (typeof body.id !== "string" || !body.patch || typeof body.patch !== "object") {
    return apiErrorResponse(request, "invalid_team_entry_update", 400, {
      message: "invalid team entry update"
    });
  }

  try {
    const before = (await getTeamEntries(auth.session.teamId)).find(
      (entry) => entry.id === body.id
    );
    if (!before) throw new Error("team entry not found");
    const entry = await updateTeamEntry(
      auth.session.teamId,
      body.id,
      body.patch as Partial<TeamEntry>
    );
    await recordAuditLog({
      action: "team_entry.update",
      actor_id: auth.session.id,
      after_jsonb: entry,
      before_jsonb: before,
      target_id: entry.id,
      target_type: "team_entry",
      team_id: auth.session.teamId
    });
    return NextResponse.json({
      entry
    });
  } catch (error) {
    return apiErrorResponse(request, "team_entry_not_found", 404, {
      message: error instanceof Error ? error.message : "update failed"
    });
  }
}

export async function DELETE(request: NextRequest) {
  const auth = await requireAdmin(request);
  if ("error" in auth) return auth.error;
  const id = request.nextUrl.searchParams.get("id");
  if (!id) {
    return apiErrorResponse(request, "missing_id", 400, { message: "id is required" });
  }
  if (request.nextUrl.searchParams.get("confirm") !== id) {
    return apiErrorResponse(request, "confirmation_required", 400, {
      message: "confirmation required"
    });
  }

  try {
    const entry = await deleteTeamEntry(auth.session.teamId, id);
    await recordAuditLog({
      action: "team_entry.deprecate",
      actor_id: auth.session.id,
      after_jsonb: { deprecated: true, deprecated_reason: "admin removed" },
      before_jsonb: entry,
      target_id: entry.id,
      target_type: "team_entry",
      team_id: auth.session.teamId
    });
    return NextResponse.json({ entry });
  } catch (error) {
    return apiErrorResponse(request, "team_entry_not_found", 404, {
      message: error instanceof Error ? error.message : "delete failed"
    });
  }
}
