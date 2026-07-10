import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { recordAuditLog } from "@/lib/audit-log";
import { hasApiScope, resolveApiIdentity } from "@/lib/api-identity";
import {
  deleteTeamsInstallByTenantId,
  upsertTeamsInstall,
  type TeamsInstallAuthType,
  type TeamsInstallRecord,
  type UpsertTeamsInstallInput
} from "@/lib/teams-installs";
import { incrementTeamsMetric } from "@/lib/teams-monitoring";

interface TeamsInstallDeps {
  deleteInstall?: typeof deleteTeamsInstallByTenantId;
  upsertInstall?: typeof upsertTeamsInstall;
}

export async function postTeamsInstallation(request: NextRequest, deps: TeamsInstallDeps = {}) {
  const identity = await resolveApiIdentity(request.headers);
  if (!identity.ok) return apiErrorResponse(request, identity.error, identity.status);
  if (identity.identity.type !== "api") {
    return apiErrorResponse(request, "missing_api_scope", 401, {
      message: "api token is required"
    });
  }
  if (!hasApiScope(identity.identity, "admin")) {
    return apiErrorResponse(request, "insufficient_api_scope", 403, {
      message: "admin scope is required"
    });
  }
  if (!identity.identity.teamId) {
    return apiErrorResponse(request, "missing_team_scope", 403, {
      message: "team-scoped API key is required"
    });
  }

  const parsed = parseTeamsInstallBody((await request.json()) as unknown, identity.identity.teamId);
  if (!parsed.ok) {
    incrementTeamsMetric("teams_install_total", { outcome: "invalid" });
    return apiErrorResponse(request, "invalid_teams_install", 400, { message: parsed.error });
  }

  try {
    const install = await (deps.upsertInstall ?? upsertTeamsInstall)({
      ...parsed.input,
      installedBy: identity.identity.userId
    });
    await recordAuditLog({
      action: "teams_install.upsert",
      actor_id: identity.identity.createdBy ?? null,
      after_jsonb: {
        app_id: install.app_id,
        auth_type: install.auth_type,
        id: install.id,
        microsoft_tenant_id: install.microsoft_tenant_id,
        service_url: install.service_url,
        tenant_name: install.tenant_name
      },
      before_jsonb: null,
      target_id: install.id,
      target_type: "teams_install",
      team_id: identity.identity.teamId
    });
    incrementTeamsMetric("teams_install_total", { outcome: "upserted" });
    return NextResponse.json({ install }, { status: 201 });
  } catch (error) {
    incrementTeamsMetric("teams_install_total", { outcome: "failed" });
    return apiErrorResponse(request, "teams_install_failed", 500, {
      message: error instanceof Error ? error.message : "Teams install failed"
    });
  }
}

export async function deleteTeamsInstallation(request: NextRequest, deps: TeamsInstallDeps = {}) {
  const identity = await resolveApiIdentity(request.headers);
  if (!identity.ok) return apiErrorResponse(request, identity.error, identity.status);
  if (identity.identity.type !== "api") {
    return apiErrorResponse(request, "missing_api_scope", 401, {
      message: "api token is required"
    });
  }
  if (!hasApiScope(identity.identity, "admin")) {
    return apiErrorResponse(request, "insufficient_api_scope", 403, {
      message: "admin scope is required"
    });
  }
  if (!identity.identity.teamId) {
    return apiErrorResponse(request, "missing_team_scope", 403, {
      message: "team-scoped API key is required"
    });
  }

  const microsoftTenantId = request.nextUrl.searchParams.get("tenant_id")?.trim();
  if (!microsoftTenantId) {
    incrementTeamsMetric("teams_install_total", { outcome: "invalid_delete" });
    return apiErrorResponse(request, "invalid_teams_install", 400, {
      message: "tenant_id is required"
    });
  }

  const deleted = await (deps.deleteInstall ?? deleteTeamsInstallByTenantId)(
    microsoftTenantId,
    identity.identity.teamId
  );
  if (deleted) {
    await recordAuditLog({
      action: "teams_install.delete",
      actor_id: identity.identity.createdBy ?? null,
      after_jsonb: { deleted: true },
      before_jsonb: { microsoft_tenant_id: microsoftTenantId },
      target_id: microsoftTenantId,
      target_type: "teams_install",
      team_id: identity.identity.teamId
    });
  }
  incrementTeamsMetric("teams_install_total", {
    outcome: deleted ? "deleted" : "not_found"
  });
  return NextResponse.json({ deleted });
}

function parseTeamsInstallBody(
  body: unknown,
  teamId: string
): { input: UpsertTeamsInstallInput; ok: true } | { error: string; ok: false } {
  if (!body || typeof body !== "object") return { error: "body must be an object", ok: false };
  const value = body as Record<string, unknown>;
  const microsoftTenantId = stringValue(value.microsoft_tenant_id ?? value.microsoftTenantId);
  const appId = stringValue(value.app_id ?? value.appId);
  const authType = stringValue(value.auth_type ?? value.authType) as TeamsInstallAuthType | null;

  if (!microsoftTenantId) return { error: "microsoft_tenant_id is required", ok: false };
  if (!appId) return { error: "app_id is required", ok: false };
  if (authType !== "apiSecretServiceAuth" && authType !== "microsoftEntra") {
    return { error: "auth_type must be apiSecretServiceAuth or microsoftEntra", ok: false };
  }

  return {
    input: {
      apiSecretRegistrationId: stringValue(
        value.api_secret_registration_id ?? value.apiSecretRegistrationId
      ),
      appId,
      authType,
      microsoftTenantId,
      serviceUrl: stringValue(value.service_url ?? value.serviceUrl),
      teamId,
      tenantName: stringValue(value.tenant_name ?? value.tenantName)
    },
    ok: true
  };
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

export type { TeamsInstallRecord };
