import type { AdapterAccount } from "next-auth/adapters";
import { beforeEach, describe, expect, it, vi } from "vitest";

const db = vi.hoisted(() => ({
  queries: [] as Array<{ sql: string; values?: unknown[] }>
}));

vi.mock("@/lib/auth-db", () => ({
  authDb: () => ({
    async query<Row>(sql: string, values?: unknown[]) {
      db.queries.push({ sql, values });
      if (sql.includes("insert into accounts")) {
        return {
          rows: [
            {
              access_token: values?.[5] ?? null,
              expires_at: values?.[6] ?? null,
              id_token: values?.[9] ?? null,
              provider: values?.[2],
              provider_account_id: values?.[3],
              refresh_token: values?.[4] ?? null,
              scope: values?.[8] ?? null,
              session_state: values?.[10] ?? null,
              token_type: values?.[7] ?? null,
              type: values?.[1],
              user_id: values?.[0]
            } as Row
          ]
        };
      }
      return { rows: [] };
    }
  })
}));

import { watNextAuthAdapter } from "./next-auth-adapter";
import { decryptOAuthToken, isEncryptedOAuthToken } from "./oauth-token-encryption";

const env = {
  AUTH_TOKEN_ENCRYPTION_KEY: "oauth_token_key_012345678901234567890123456789"
};

describe("watNextAuthAdapter account tokens", () => {
  beforeEach(() => {
    db.queries.length = 0;
    process.env.AUTH_TOKEN_ENCRYPTION_KEY = env.AUTH_TOKEN_ENCRYPTION_KEY;
  });

  it("encrypts OAuth tokens before storing account rows", async () => {
    const account = (await watNextAuthAdapter().linkAccount?.({
      access_token: "access-secret",
      expires_at: 1,
      id_token: "id-secret",
      provider: "google",
      providerAccountId: "google-user",
      refresh_token: "refresh-secret",
      scope: "openid email",
      token_type: "bearer",
      type: "oauth",
      userId: "user_1"
    } satisfies AdapterAccount))!;

    const values = db.queries[0]?.values ?? [];
    for (const index of [4, 5, 9]) {
      expect(isEncryptedOAuthToken(String(values[index]))).toBe(true);
    }
    expect(JSON.stringify(values)).not.toContain("access-secret");
    expect(JSON.stringify(values)).not.toContain("refresh-secret");
    expect(JSON.stringify(values)).not.toContain("id-secret");
    expect(decryptOAuthToken(String(values[5]), env)).toBe("access-secret");
    expect(account.access_token).toBe("access-secret");
    expect(account.refresh_token).toBe("refresh-secret");
    expect(account.id_token).toBe("id-secret");
  });
});
