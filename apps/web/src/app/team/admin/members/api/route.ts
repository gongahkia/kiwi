import { NextResponse, type NextRequest } from "next/server";

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
    return NextResponse.json({ error: "invalid member update" }, { status: 400 });
  }

  try {
    return NextResponse.json({ member: setTeamMemberRole(body.id, body.role) });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "member update failed" },
      { status: 404 }
    );
  }
}

export async function DELETE(request: NextRequest) {
  const id = request.nextUrl.searchParams.get("id");
  if (!id) {
    return NextResponse.json({ error: "id is required" }, { status: 400 });
  }

  try {
    return NextResponse.json({ member: removeTeamMember(id) });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "member removal failed" },
      { status: 404 }
    );
  }
}
