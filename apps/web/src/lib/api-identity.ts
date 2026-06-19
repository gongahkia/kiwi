import { timingSafeEqual } from "node:crypto";

export interface ApiIdentity {
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
      error: "invalid_api_key";
      ok: false;
      status: 401;
    };

interface ApiIdentityEnv {
  [key: string]: string | undefined;
  WAT_API_KEY?: string;
}

function sameSecret(left: string, right: string): boolean {
  const leftBytes = Buffer.from(left);
  const rightBytes = Buffer.from(right);

  return leftBytes.length === rightBytes.length && timingSafeEqual(leftBytes, rightBytes);
}

function apiKeyFromHeaders(headers: Headers): string | null {
  const xApiKey = headers.get("x-api-key")?.trim();
  if (xApiKey) {
    return xApiKey;
  }

  const authorization = headers.get("authorization");
  const match = authorization?.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() ?? null;
}

export function resolveApiIdentity(
  headers: Headers,
  env: ApiIdentityEnv = process.env
): ApiIdentityResult {
  const apiKey = apiKeyFromHeaders(headers);
  if (!apiKey) {
    return { identity: { type: "anonymous" }, ok: true };
  }
  if (!env.WAT_API_KEY || !sameSecret(apiKey, env.WAT_API_KEY)) {
    return { error: "invalid_api_key", ok: false, status: 401 };
  }

  return {
    identity: {
      teamId: headers.get("x-wat-team-id")?.trim() || undefined,
      tokenId: "wat_api_key",
      type: "api",
      userId: headers.get("x-wat-user-id")?.trim() || "api"
    },
    ok: true
  };
}
