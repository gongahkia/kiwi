import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { recordAuditLog } from "@/lib/audit-log";
import { createApiKey, listApiKeys, revokeApiKey, type ApiKeyScope } from "@/lib/api-keys";
import { sessionUserFromRequest, type WatSessionUser } from "@/lib/session";

function scopesFromBody(value: unknown): ApiKeyScope[] | undefined {
  if (value == null) return undefined;
  if (!Array.isArray(value)) return [];
  const scopes = value.filter((scope): scope is ApiKeyScope =>
    ["admin", "search", "suggest", "write"].includes(String(scope))
  );
  return scopes.length === value.length ? scopes : [];
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
  const auth = await requireAdmin(request);
  if ("error" in auth) return auth.error;
  return NextResponse.json({ keys: await listApiKeys(auth.session.teamId) });
}

export async function POST(request: NextRequest) {
  const auth = await requireAdmin(request);
  if ("error" in auth) return auth.error;
  const body = (await request.json()) as { name?: unknown; scopes?: unknown };
  if (body.name != null && (typeof body.name !== "string" || !body.name.trim())) {
    return apiErrorResponse(request, "invalid_api_key", 400, { message: "name is required" });
  }
  const scopes = scopesFromBody(body.scopes);
  if (scopes?.length === 0) {
    return apiErrorResponse(request, "invalid_api_key", 400, { message: "invalid scopes" });
  }
  const key = await createApiKey({
    createdBy: auth.session.id,
    name: typeof body.name === "string" ? body.name : "Team API key",
    scopes,
    teamId: auth.session.teamId
  });
  await recordAuditLog({
    action: "api_key.create",
    actor_id: auth.session.id,
    after_jsonb: { id: key.id, key_prefix: key.key_prefix, name: key.name, scopes: key.scopes },
    before_jsonb: null,
    target_id: key.id,
    target_type: "api_key",
    team_id: auth.session.teamId
  });
  return NextResponse.json({ key }, { status: 201 });
}

export async function DELETE(request: NextRequest) {
  const auth = await requireAdmin(request);
  if ("error" in auth) return auth.error;
  const id = request.nextUrl.searchParams.get("id");
  if (!id) return apiErrorResponse(request, "missing_id", 400, { message: "id is required" });
  if (request.nextUrl.searchParams.get("confirm") !== id) {
    return apiErrorResponse(request, "confirmation_required", 400, {
      message: "confirmation required"
    });
  }
  try {
    const key = await revokeApiKey(auth.session.teamId, id);
    await recordAuditLog({
      action: "api_key.revoke",
      actor_id: auth.session.id,
      after_jsonb: { revoked_at: key.revoked_at },
      before_jsonb: { id: key.id, key_prefix: key.key_prefix, name: key.name, scopes: key.scopes },
      target_id: key.id,
      target_type: "api_key",
      team_id: auth.session.teamId
    });
    return NextResponse.json({ key });
  } catch (error) {
    return apiErrorResponse(request, "api_key_not_found", 404, {
      message: error instanceof Error ? error.message : "api key not found"
    });
  }
}
