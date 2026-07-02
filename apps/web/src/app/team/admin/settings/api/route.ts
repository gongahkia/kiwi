import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { recordAuditLog } from "@/lib/audit-log";
import { sessionUserFromRequest, type WatSessionUser } from "@/lib/session";
import { getTeamProfile, updateTeamProfile, type TeamProfile } from "@/lib/team-profile";
import { getTeamSettings, updateTeamSettings, type TeamSettings } from "@/lib/team-settings";

interface TeamSettingsUpdate {
  profile?: Partial<TeamProfile>;
  settings?: Partial<TeamSettings>;
}

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

function isProfilePatch(value: unknown): value is Partial<TeamProfile> {
  if (!value || typeof value !== "object") return false;
  const patch = value as Partial<TeamProfile>;
  return (
    (patch.name == null || typeof patch.name === "string") &&
    (patch.email_domain == null || typeof patch.email_domain === "string")
  );
}

function isUpdateBody(value: unknown): value is TeamSettingsUpdate {
  if (!value || typeof value !== "object") return false;
  const body = value as TeamSettingsUpdate;
  return (
    (body.profile == null || isProfilePatch(body.profile)) &&
    (body.settings == null || isSettingsPatch(body.settings))
  );
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
  const [profile, settings] = await Promise.all([
    getTeamProfile(session.teamId),
    getTeamSettings(session.teamId)
  ]);
  return NextResponse.json({ profile, settings });
}

export async function POST(request: NextRequest) {
  const auth = await requireAdmin(request);
  if ("error" in auth) return auth.error;
  const body = (await request.json()) as unknown;
  if (!isUpdateBody(body)) {
    return apiErrorResponse(request, "invalid_team_settings", 400, {
      message: "invalid team settings"
    });
  }

  const [beforeProfile, beforeSettings] = await Promise.all([
    getTeamProfile(auth.session.teamId),
    getTeamSettings(auth.session.teamId)
  ]);
  const [profile, settings] = await Promise.all([
    body.profile ? updateTeamProfile(auth.session.teamId, body.profile) : beforeProfile,
    body.settings ? updateTeamSettings(auth.session.teamId, body.settings) : beforeSettings
  ]);
  await recordAuditLog({
    action: "team.settings.update",
    actor_id: auth.session.id,
    after_jsonb: { profile, settings },
    before_jsonb: { profile: beforeProfile, settings: beforeSettings },
    target_id: auth.session.teamId,
    target_type: "team",
    team_id: auth.session.teamId
  });
  return NextResponse.json({ profile, settings });
}
