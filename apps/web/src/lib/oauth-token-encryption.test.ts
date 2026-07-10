import { describe, expect, it } from "vitest";

import {
  decryptOAuthToken,
  encryptOAuthToken,
  isEncryptedOAuthToken
} from "./oauth-token-encryption";

const env = {
  AUTH_TOKEN_ENCRYPTION_KEY: "oauth_token_key_012345678901234567890123456789"
};

describe("OAuth token encryption", () => {
  it("encrypts and decrypts tokens", () => {
    const encrypted = encryptOAuthToken("oauth-secret-token", env);

    expect(encrypted).toBeTruthy();
    expect(encrypted).not.toContain("oauth-secret-token");
    expect(encrypted && isEncryptedOAuthToken(encrypted)).toBe(true);
    expect(decryptOAuthToken(encrypted, env)).toBe("oauth-secret-token");
  });

  it("uses a fresh nonce per token", () => {
    expect(encryptOAuthToken("oauth-secret-token", env)).not.toBe(
      encryptOAuthToken("oauth-secret-token", env)
    );
  });

  it("keeps legacy plaintext readable", () => {
    expect(decryptOAuthToken("legacy-token", {})).toBe("legacy-token");
  });

  it("requires a key for new encrypted tokens", () => {
    expect(() => encryptOAuthToken("oauth-secret-token", {})).toThrow(
      "AUTH_TOKEN_ENCRYPTION_KEY is required"
    );
  });
});
