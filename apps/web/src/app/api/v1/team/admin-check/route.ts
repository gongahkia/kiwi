import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { resolveApiIdentity } from "@/lib/api-identity";
import { getTeamMember } from "@/lib/team-members";

export const runtime = "nodejs";

export async function GET(request: NextRequest) {
  const identity = await resolveApiIdentity(request.headers);
  if (!identity.ok) {
    return apiErrorResponse(request, identity.error, identity.status);
  }
  if (identity.identity.type !== "api") {
    return apiErrorResponse(request, "missing_api_scope", 401, {
      message: "api token is required"
    });
  }
  if (!identity.identity.teamId) {
    return apiErrorResponse(request, "missing_team_scope", 403, {
      message: "x-wat-team-id is required"
    });
  }

  const user = request.nextUrl.searchParams.get("user")?.trim();
  if (!user) {
    return apiErrorResponse(request, "missing_user", 400, {
      message: "user is required"
    });
  }

  const member = await getTeamMember(identity.identity.teamId, user);
  return NextResponse.json({
    admin: member?.role === "admin",
    team_id: identity.identity.teamId,
    user
  });
}
