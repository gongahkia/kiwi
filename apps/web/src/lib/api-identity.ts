import { lookupApiKey, type ApiKeyScope } from "@/lib/api-keys";

export interface ApiIdentity {
  scopes?: ApiKeyScope[];
  teamId?: string;
  tokenId?: string;
  type: "anonymous" | "api";
  userId?: string;
}

export type ApiIdentityResult =
  | {
      identity: ApiIdentity;
      ok: true;
    }
  | {
      error: "invalid_api_key" | "team_scope_mismatch";
      ok: false;
      status: 401 | 403;
    };

function apiKeyFromHeaders(headers: Headers): string | null {
  const xApiKey = headers.get("x-api-key")?.trim();
  if (xApiKey) return xApiKey;

  const authorization = headers.get("authorization");
  const match = authorization?.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() ?? null;
}

export async function resolveApiIdentity(headers: Headers): Promise<ApiIdentityResult> {
  const apiKey = apiKeyFromHeaders(headers);
  if (!apiKey) return { identity: { type: "anonymous" }, ok: true };

  const record = await lookupApiKey(apiKey);
  if (!record) return { error: "invalid_api_key", ok: false, status: 401 };

  const requestedTeamId = headers.get("x-wat-team-id")?.trim();
  if (requestedTeamId && requestedTeamId !== record.team_id) {
    return { error: "team_scope_mismatch", ok: false, status: 403 };
  }

  return {
    identity: {
      scopes: record.scopes,
      teamId: record.team_id,
      tokenId: record.id,
      type: "api",
      userId: headers.get("x-wat-user-id")?.trim() || undefined
    },
    ok: true
  };
}

export function hasApiScope(
  identity: ApiIdentity,
  scope: "admin" | "search" | "suggest" | "write"
): boolean {
  if (identity.type !== "api") return false;
  const scopes = identity.scopes ?? [];
  return scopes.includes("admin") || scopes.includes(scope);
}
