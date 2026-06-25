import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { resolveApiIdentity } from "@/lib/api-identity";
import {
  deleteDiscordInstallByGuildId,
  upsertDiscordInstall,
  type DiscordInstallRecord,
  type UpsertDiscordInstallInput
} from "@/lib/discord-installs";
import { incrementDiscordMetric } from "@/lib/discord-monitoring";

interface DiscordInstallDeps {
  deleteInstall?: typeof deleteDiscordInstallByGuildId;
  upsertInstall?: typeof upsertDiscordInstall;
}

export async function postDiscordInstallation(request: NextRequest, deps: DiscordInstallDeps = {}) {
  const identity = await resolveApiIdentity(request.headers);
  if (!identity.ok) return apiErrorResponse(request, identity.error, identity.status);
  if (identity.identity.type !== "api") {
    return apiErrorResponse(request, "missing_api_scope", 401, {
      message: "api token is required"
    });
  }
  if (!identity.identity.teamId) {
    return apiErrorResponse(request, "missing_team_scope", 403, {
      message: "x-wat-team-id or WAT_TEAM_ID is required"
    });
  }

  const parsed = parseDiscordInstallBody(
    (await request.json()) as unknown,
    identity.identity.teamId
  );
  if (!parsed.ok) {
    incrementDiscordMetric("discord_install_total", { outcome: "invalid" });
    return apiErrorResponse(request, "invalid_discord_install", 400, { message: parsed.error });
  }

  try {
    const install = await (deps.upsertInstall ?? upsertDiscordInstall)({
      ...parsed.input,
      installerDiscordUserId: parsed.input.installerDiscordUserId ?? identity.identity.userId
    });
    incrementDiscordMetric("discord_install_total", { outcome: "upserted" });
    return NextResponse.json({ install }, { status: 201 });
  } catch (error) {
    incrementDiscordMetric("discord_install_total", { outcome: "failed" });
    return apiErrorResponse(request, "discord_install_failed", 500, {
      message: error instanceof Error ? error.message : "Discord install failed"
    });
  }
}

export async function deleteDiscordInstallation(
  request: NextRequest,
  deps: DiscordInstallDeps = {}
) {
  const identity = await resolveApiIdentity(request.headers);
  if (!identity.ok) return apiErrorResponse(request, identity.error, identity.status);
  if (identity.identity.type !== "api") {
    return apiErrorResponse(request, "missing_api_scope", 401, {
      message: "api token is required"
    });
  }
  if (!identity.identity.teamId) {
    return apiErrorResponse(request, "missing_team_scope", 403, {
      message: "x-wat-team-id or WAT_TEAM_ID is required"
    });
  }

  const discordGuildId = request.nextUrl.searchParams.get("guild_id")?.trim();
  if (!discordGuildId) {
    incrementDiscordMetric("discord_install_total", { outcome: "invalid_delete" });
    return apiErrorResponse(request, "invalid_discord_install", 400, {
      message: "guild_id is required"
    });
  }

  const deleted = await (deps.deleteInstall ?? deleteDiscordInstallByGuildId)(
    discordGuildId,
    identity.identity.teamId
  );
  incrementDiscordMetric("discord_install_total", {
    outcome: deleted ? "deleted" : "not_found"
  });
  return NextResponse.json({ deleted });
}

function parseDiscordInstallBody(
  body: unknown,
  teamId: string
): { input: UpsertDiscordInstallInput; ok: true } | { error: string; ok: false } {
  if (!body || typeof body !== "object") return { error: "body must be an object", ok: false };
  const value = body as Record<string, unknown>;
  const discordGuildId = stringValue(value.discord_guild_id ?? value.discordGuildId);
  const applicationId = stringValue(value.application_id ?? value.applicationId);
  if (!discordGuildId) return { error: "discord_guild_id is required", ok: false };
  if (!applicationId) return { error: "application_id is required", ok: false };

  return {
    input: {
      adminRoleIds: stringArrayValue(value.admin_role_ids ?? value.adminRoleIds),
      applicationId,
      botUserId: stringValue(value.bot_user_id ?? value.botUserId),
      discordGuildId,
      guildName: stringValue(value.guild_name ?? value.guildName),
      installerDiscordUserId: stringValue(
        value.installer_discord_user_id ?? value.installerDiscordUserId
      ),
      teamId
    },
    ok: true
  };
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function stringArrayValue(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  const cleaned = value
    .filter((item): item is string => typeof item === "string" && Boolean(item.trim()))
    .map((item) => item.trim());
  return cleaned.length > 0 ? Array.from(new Set(cleaned)) : undefined;
}

export type { DiscordInstallRecord };
