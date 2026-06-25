import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { pageInfo, paginationWindow } from "@/lib/pagination";
import { sessionUserFromRequest } from "@/lib/session";
import {
  createTeamEntry,
  deleteTeamEntry,
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
  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  const body = (await request.json()) as unknown;
  if (!isTeamEntry(body)) {
    return apiErrorResponse(request, "invalid_team_entry", 400, {
      message: "invalid team entry"
    });
  }

  try {
    return NextResponse.json({ entry: await createTeamEntry(session.teamId, body) });
  } catch (error) {
    return apiErrorResponse(request, "team_entry_conflict", 409, {
      message: error instanceof Error ? error.message : "create failed"
    });
  }
}

export async function PATCH(request: NextRequest) {
  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  const body = (await request.json()) as { id?: unknown; patch?: unknown };
  if (typeof body.id !== "string" || !body.patch || typeof body.patch !== "object") {
    return apiErrorResponse(request, "invalid_team_entry_update", 400, {
      message: "invalid team entry update"
    });
  }

  try {
    return NextResponse.json({
      entry: await updateTeamEntry(session.teamId, body.id, body.patch as Partial<TeamEntry>)
    });
  } catch (error) {
    return apiErrorResponse(request, "team_entry_not_found", 404, {
      message: error instanceof Error ? error.message : "update failed"
    });
  }
}

export async function DELETE(request: NextRequest) {
  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  const id = request.nextUrl.searchParams.get("id");
  if (!id) {
    return apiErrorResponse(request, "missing_id", 400, { message: "id is required" });
  }

  try {
    return NextResponse.json({ entry: await deleteTeamEntry(session.teamId, id) });
  } catch (error) {
    return apiErrorResponse(request, "team_entry_not_found", 404, {
      message: error instanceof Error ? error.message : "delete failed"
    });
  }
}
