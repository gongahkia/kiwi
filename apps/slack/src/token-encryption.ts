import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";

const algorithm = "aes-256-gcm";
const keyBytes = 32;
const ivBytes = 12;

export interface EncryptedToken {
  ciphertext: string;
  iv: string;
  tag: string;
  version: 1;
}

function deriveKey(rawKey: string): Buffer {
  if (!rawKey) {
    throw new Error("SLACK_TOKEN_ENCRYPTION_KEY is required");
  }

  return createHash("sha256").update(rawKey).digest().subarray(0, keyBytes);
}

export function encryptToken(token: string, rawKey: string): EncryptedToken {
  const iv = randomBytes(ivBytes);
  const cipher = createCipheriv(algorithm, deriveKey(rawKey), iv);
  const ciphertext = Buffer.concat([cipher.update(token, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();

  return {
    ciphertext: ciphertext.toString("base64url"),
    iv: iv.toString("base64url"),
    tag: tag.toString("base64url"),
    version: 1
  };
}

export function decryptToken(payload: EncryptedToken, rawKey: string): string {
  const decipher = createDecipheriv(
    algorithm,
    deriveKey(rawKey),
    Buffer.from(payload.iv, "base64url")
  );
  decipher.setAuthTag(Buffer.from(payload.tag, "base64url"));

  return Buffer.concat([
    decipher.update(Buffer.from(payload.ciphertext, "base64url")),
    decipher.final()
  ]).toString("utf8");
}
