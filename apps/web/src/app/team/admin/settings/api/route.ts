import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { sessionUserFromRequest } from "@/lib/session";
import { getTeamSettings, updateTeamSettings, type TeamSettings } from "@/lib/team-settings";

function isSettingsPatch(value: unknown): value is Partial<TeamSettings> {
  if (!value || typeof value !== "object") {
    return false;
  }

  const patch = value as Partial<TeamSettings>;
  return (
    (patch.allow_public_layer == null || typeof patch.allow_public_layer === "boolean") &&
    (patch.default_domain_filter == null || typeof patch.default_domain_filter === "string") &&
    (patch.domain_tags == null ||
      (Array.isArray(patch.domain_tags) &&
        patch.domain_tags.every((tag) => typeof tag === "string")))
  );
}

export async function GET(request: NextRequest) {
  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  return NextResponse.json(await getTeamSettings(session.teamId));
}

export async function POST(request: NextRequest) {
  const session = await sessionUserFromRequest(request);
  if (!session?.teamId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }
  const body = (await request.json()) as unknown;
  if (!isSettingsPatch(body)) {
    return apiErrorResponse(request, "invalid_team_settings", 400, {
      message: "invalid team settings"
    });
  }

  return NextResponse.json(await updateTeamSettings(session.teamId, body));
}
