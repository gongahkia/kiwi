import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import {
  getTeamMembers,
  removeTeamMember,
  setTeamMemberRole,
  type TeamRole
} from "@/lib/team-members";

function isRole(value: unknown): value is TeamRole {
  return value === "admin" || value === "member";
}

export function GET() {
  return NextResponse.json({ members: getTeamMembers() });
}

export async function PATCH(request: NextRequest) {
  const body = (await request.json()) as { id?: unknown; role?: unknown };
  if (typeof body.id !== "string" || !isRole(body.role)) {
    return apiErrorResponse(request, "invalid_member_update", 400, {
      message: "invalid member update"
    });
  }

  try {
    return NextResponse.json({ member: setTeamMemberRole(body.id, body.role) });
  } catch (error) {
    return apiErrorResponse(request, "member_not_found", 404, {
      message: error instanceof Error ? error.message : "member update failed"
    });
  }
}

export async function DELETE(request: NextRequest) {
  const id = request.nextUrl.searchParams.get("id");
  if (!id) {
    return apiErrorResponse(request, "missing_id", 400, { message: "id is required" });
  }

  try {
    return NextResponse.json({ member: removeTeamMember(id) });
  } catch (error) {
    return apiErrorResponse(request, "member_not_found", 404, {
      message: error instanceof Error ? error.message : "member removal failed"
    });
  }
}
