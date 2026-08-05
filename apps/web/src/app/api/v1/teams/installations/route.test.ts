import { afterEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";

import { resetApiKeysForTest, seedApiKeyForTest } from "@/lib/api-keys";
import { getAuditLog, resetAuditLogForTest } from "@/lib/audit-log";
import { resetTeamsMetricsForTest } from "@/lib/teams-monitoring";

import { deleteTeamsInstallation, postTeamsInstallation } from "./handler";

function request(body: unknown, headers: Record<string, string> = {}): NextRequest {
  return new NextRequest("https://wat.example.com/api/v1/teams/installations", {
    body: JSON.stringify(body),
    headers: {
      authorization: "Bearer test-key",
      "content-type": "application/json",
      "x-wat-team-id": "team_123",
      "x-wat-user-id": "admin@example.com",
      ...headers
    },
    method: "POST"
  });
}

const validInstall = {
  api_secret_registration_id: "secret-registration-id",
  app_id: "teams-app-id",
  auth_type: "apiSecretServiceAuth",
  microsoft_tenant_id: "tenant_123",
  tenant_name: "Example Tenant"
};

describe("Teams installations API", () => {
  afterEach(() => {
    resetAuditLogForTest();
    resetTeamsMetricsForTest();
    resetApiKeysForTest();
  });

  it("upserts a Teams tenant mapping", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_123" });
    const response = await postTeamsInstallation(request(validInstall), {
      upsertInstall: async (input) => ({
        api_secret_registration_id: input.apiSecretRegistrationId ?? null,
        app_id: input.appId,
        auth_type: input.authType,
        id: "teams-install-tenant_123",
        installed_at: "2026-06-25T00:00:00.000Z",
        installed_by: input.installedBy ?? null,
        microsoft_tenant_id: input.microsoftTenantId,
        service_url: input.serviceUrl ?? null,
        team_id: input.teamId,
        tenant_name: input.tenantName ?? null,
        updated_at: "2026-06-25T00:00:00.000Z"
      })
    });

    const body = (await response.json()) as { install?: { team_id?: string } };
    expect(response.status).toBe(201);
    expect(body.install?.team_id).toBe("team_123");
    await expect(getAuditLog("team_123")).resolves.toMatchObject([
      { action: "teams_install.upsert", target_type: "teams_install" }
    ]);
  });

  it("requires API and team scope", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_123" });

    expect(
      (await postTeamsInstallation(request(validInstall, { authorization: "Bearer bad-key" })))
        .status
    ).toBe(401);
    expect(
      (await postTeamsInstallation(request(validInstall, { "x-wat-team-id": "team_999" }))).status
    ).toBe(403);
  });

  it("rejects invalid installs", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_123" });

    const response = await postTeamsInstallation(
      request({ ...validInstall, microsoft_tenant_id: "" })
    );

    expect(response.status).toBe(400);
  });

  it("deletes a Teams tenant mapping", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_123" });
    const response = await deleteTeamsInstallation(
      new NextRequest("https://wat.example.com/api/v1/teams/installations?tenant_id=tenant_123", {
        headers: {
          authorization: "Bearer test-key",
          "x-wat-team-id": "team_123"
        },
        method: "DELETE"
      }),
      {
        deleteInstall: async (microsoftTenantId, teamId) =>
          microsoftTenantId === "tenant_123" && teamId === "team_123"
      }
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ deleted: true });
    await expect(getAuditLog("team_123")).resolves.toMatchObject([
      { action: "teams_install.delete", target_id: "tenant_123" }
    ]);
  });
});
