import { describe, expect, it } from "vitest";

import { decryptToken, encryptToken } from "./token-encryption.js";

describe("token encryption", () => {
  it("encrypts and decrypts with AES-GCM using an env-provided key", () => {
    const rawKey = "test-kms-key";
    const encrypted = encryptToken("xoxb-secret-token", rawKey);

    expect(encrypted.version).toBe(1);
    expect(encrypted.ciphertext).not.toContain("xoxb-secret-token");
    expect(decryptToken(encrypted, rawKey)).toBe("xoxb-secret-token");
  });

  it("rejects the wrong key", () => {
    const encrypted = encryptToken("xoxb-secret-token", "correct-key");

    expect(() => decryptToken(encrypted, "wrong-key")).toThrow();
  });

  it("requires an encryption key", () => {
    expect(() => encryptToken("xoxb-secret-token", "")).toThrow(
      "SLACK_TOKEN_ENCRYPTION_KEY is required"
    );
  });
});
