import { authDb } from "@/lib/auth-db";

export type TeamsInstallAuthType = "apiSecretServiceAuth" | "microsoftEntra";

export interface TeamsInstallRecord {
  api_secret_registration_id: string | null;
  app_id: string;
  auth_type: TeamsInstallAuthType;
  id: string;
  installed_at: string;
  installed_by: string | null;
  microsoft_tenant_id: string;
  service_url: string | null;
  team_id: string;
  tenant_name: string | null;
  updated_at: string;
}

export interface UpsertTeamsInstallInput {
  apiSecretRegistrationId?: string;
  appId: string;
  authType: TeamsInstallAuthType;
  installedBy?: string;
  microsoftTenantId: string;
  serviceUrl?: string;
  teamId: string;
  tenantName?: string;
}

export async function upsertTeamsInstall(
  input: UpsertTeamsInstallInput
): Promise<TeamsInstallRecord> {
  const id = `teams-install-${input.microsoftTenantId.toLowerCase()}`;
  const { rows } = await authDb().query<TeamsInstallRow>(
    `
    insert into teams_installs (
      id, microsoft_tenant_id, tenant_name, team_id, app_id, auth_type,
      api_secret_registration_id, service_url, installed_by
    ) values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    on conflict (microsoft_tenant_id) do update set
      tenant_name = excluded.tenant_name,
      team_id = excluded.team_id,
      app_id = excluded.app_id,
      auth_type = excluded.auth_type,
      api_secret_registration_id = excluded.api_secret_registration_id,
      service_url = excluded.service_url,
      installed_by = excluded.installed_by,
      updated_at = now()
    returning
      id, microsoft_tenant_id, tenant_name, team_id, app_id, auth_type,
      api_secret_registration_id, service_url, installed_by, installed_at, updated_at
    `,
    [
      id,
      input.microsoftTenantId,
      input.tenantName ?? null,
      input.teamId,
      input.appId,
      input.authType,
      input.apiSecretRegistrationId ?? null,
      input.serviceUrl ?? null,
      input.installedBy ?? null
    ]
  );
  const row = rows[0];
  if (!row) throw new Error("Teams install upsert failed");
  return teamsInstallFromRow(row);
}

export async function getTeamsInstallByTenantId(
  microsoftTenantId: string
): Promise<TeamsInstallRecord | null> {
  const { rows } = await authDb().query<TeamsInstallRow>(
    `
    select
      id, microsoft_tenant_id, tenant_name, team_id, app_id, auth_type,
      api_secret_registration_id, service_url, installed_by, installed_at, updated_at
    from teams_installs
    where microsoft_tenant_id = $1
    `,
    [microsoftTenantId]
  );
  return rows[0] ? teamsInstallFromRow(rows[0]) : null;
}

export async function deleteTeamsInstallByTenantId(
  microsoftTenantId: string,
  teamId: string
): Promise<boolean> {
  const { rowCount } = await authDb().query(
    "delete from teams_installs where microsoft_tenant_id = $1 and team_id = $2",
    [microsoftTenantId, teamId]
  );
  return (rowCount ?? 0) > 0;
}

interface TeamsInstallRow {
  api_secret_registration_id: string | null;
  app_id: string;
  auth_type: TeamsInstallAuthType;
  id: string;
  installed_at: Date | string;
  installed_by: string | null;
  microsoft_tenant_id: string;
  service_url: string | null;
  team_id: string;
  tenant_name: string | null;
  updated_at: Date | string;
}

function teamsInstallFromRow(row: TeamsInstallRow): TeamsInstallRecord {
  return {
    api_secret_registration_id: row.api_secret_registration_id,
    app_id: row.app_id,
    auth_type: row.auth_type,
    id: row.id,
    installed_at: timestampString(row.installed_at),
    installed_by: row.installed_by,
    microsoft_tenant_id: row.microsoft_tenant_id,
    service_url: row.service_url,
    team_id: row.team_id,
    tenant_name: row.tenant_name,
    updated_at: timestampString(row.updated_at)
  };
}

function timestampString(value: Date | string): string {
  return value instanceof Date ? value.toISOString() : value;
}
