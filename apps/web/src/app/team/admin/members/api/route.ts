import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { sessionUserFromRequest } from "@/lib/session";
import {
  getTeamMembers,
  removeTeamMember,
  setTeamMemberRole,
  type TeamRole
} from "@/lib/team-members";

function isRole(value: unknown): value is TeamRole {
  return value === "admin" || value === "member";
}

export async function GET(request: NextRequest) {
  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  return NextResponse.json({ members: await getTeamMembers(session.teamId) });
}

export async function PATCH(request: NextRequest) {
  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  const body = (await request.json()) as { id?: unknown; role?: unknown };
  if (typeof body.id !== "string" || !isRole(body.role)) {
    return apiErrorResponse(request, "invalid_member_update", 400, {
      message: "invalid member update"
    });
  }

  try {
    return NextResponse.json({
      member: await setTeamMemberRole(session.teamId, body.id, body.role)
    });
  } catch (error) {
    return apiErrorResponse(request, "member_not_found", 404, {
      message: error instanceof Error ? error.message : "member update failed"
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
    return NextResponse.json({ member: await removeTeamMember(session.teamId, id) });
  } catch (error) {
    return apiErrorResponse(request, "member_not_found", 404, {
      message: error instanceof Error ? error.message : "member removal failed"
    });
  }
}
