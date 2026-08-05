import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";

type OAuthTokenEnv = Record<string, string | undefined> & {
  AUTH_TOKEN_ENCRYPTION_KEY?: string;
};

const prefix = "watenc:v1:";

function encryptionKey(env: OAuthTokenEnv = process.env): Buffer {
  const raw = env.AUTH_TOKEN_ENCRYPTION_KEY?.trim();
  if (!raw) throw new Error("AUTH_TOKEN_ENCRYPTION_KEY is required for OAuth token encryption");
  return createHash("sha256").update(raw).digest();
}

export function isEncryptedOAuthToken(value: string): boolean {
  return value.startsWith(prefix);
}

export function encryptOAuthToken(
  token: string | null | undefined,
  env: OAuthTokenEnv = process.env
): string | null {
  if (!token) return null;
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey(env), iv);
  const ciphertext = Buffer.concat([cipher.update(token, "utf8"), cipher.final()]);
  const payload = {
    c: ciphertext.toString("base64url"),
    i: iv.toString("base64url"),
    t: cipher.getAuthTag().toString("base64url")
  };
  return `${prefix}${Buffer.from(JSON.stringify(payload), "utf8").toString("base64url")}`;
}

export function decryptOAuthToken(
  value: string | null | undefined,
  env: OAuthTokenEnv = process.env
): string | null {
  if (!value) return null;
  if (!isEncryptedOAuthToken(value)) return value;

  const decoded = Buffer.from(value.slice(prefix.length), "base64url").toString("utf8");
  const payload = JSON.parse(decoded) as Partial<Record<"c" | "i" | "t", string>>;
  if (!payload.c || !payload.i || !payload.t) throw new Error("invalid OAuth token payload");

  const decipher = createDecipheriv(
    "aes-256-gcm",
    encryptionKey(env),
    Buffer.from(payload.i, "base64url")
  );
  decipher.setAuthTag(Buffer.from(payload.t, "base64url"));
  return Buffer.concat([
    decipher.update(Buffer.from(payload.c, "base64url")),
    decipher.final()
  ]).toString("utf8");
}
