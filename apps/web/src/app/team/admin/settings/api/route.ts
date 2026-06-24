import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
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

export function GET() {
  return NextResponse.json(getTeamSettings());
}

export async function POST(request: NextRequest) {
  const body = (await request.json()) as unknown;
  if (!isSettingsPatch(body)) {
    return apiErrorResponse(request, "invalid_team_settings", 400, {
      message: "invalid team settings"
    });
  }

  return NextResponse.json(updateTeamSettings(body));
}
