import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { recordAuditLog } from "@/lib/audit-log";
import { sessionUserFromRequest, type WatSessionUser } from "@/lib/session";
import { createTeamInvite, listTeamInvites } from "@/lib/team-invites";
import {
  getTeamMembers,
  removeTeamMember,
  setTeamMemberRole,
  type TeamRole
} from "@/lib/team-members";

function isRole(value: unknown): value is TeamRole {
  return value === "admin" || value === "member";
}

function isEmail(value: unknown): value is string {
  return typeof value === "string" && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim());
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
  return NextResponse.json({
    invites: await listTeamInvites(session.teamId),
    members: await getTeamMembers(session.teamId)
  });
}

export async function POST(request: NextRequest) {
  const auth = await requireAdmin(request);
  if ("error" in auth) return auth.error;
  const body = (await request.json()) as { email?: unknown; role?: unknown };
  if (!isEmail(body.email) || (body.role !== undefined && !isRole(body.role))) {
    return apiErrorResponse(request, "invalid_invite", 400, { message: "invalid invite" });
  }

  const invite = await createTeamInvite({
    email: body.email,
    invitedBy: auth.session.id,
    role: body.role,
    teamId: auth.session.teamId
  });
  await recordAuditLog({
    action: "member.invite",
    actor_id: auth.session.id,
    after_jsonb: { email: invite.email, role: invite.role },
    before_jsonb: null,
    target_id: invite.id,
    target_type: "team_invite",
    team_id: auth.session.teamId
  });

  return NextResponse.json({ invite }, { status: 201 });
}

export async function PATCH(request: NextRequest) {
  const auth = await requireAdmin(request);
  if ("error" in auth) return auth.error;
  const body = (await request.json()) as { id?: unknown; role?: unknown };
  if (typeof body.id !== "string" || !isRole(body.role)) {
    return apiErrorResponse(request, "invalid_member_update", 400, {
      message: "invalid member update"
    });
  }

  try {
    const before = await getTeamMembers(auth.session.teamId);
    const member = await setTeamMemberRole(auth.session.teamId, body.id, body.role);
    await recordAuditLog({
      action: "member.role.update",
      actor_id: auth.session.id,
      after_jsonb: member,
      before_jsonb: before.find((item) => item.id === body.id) ?? null,
      target_id: member.id,
      target_type: "user",
      team_id: auth.session.teamId
    });
    return NextResponse.json({ member });
  } catch (error) {
    return apiErrorResponse(request, "member_not_found", 404, {
      message: error instanceof Error ? error.message : "member update failed"
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
    const member = await removeTeamMember(auth.session.teamId, id);
    await recordAuditLog({
      action: "member.remove",
      actor_id: auth.session.id,
      after_jsonb: null,
      before_jsonb: member,
      target_id: member.id,
      target_type: "user",
      team_id: auth.session.teamId
    });
    return NextResponse.json({ member });
  } catch (error) {
    return apiErrorResponse(request, "member_not_found", 404, {
      message: error instanceof Error ? error.message : "member removal failed"
    });
  }
}
