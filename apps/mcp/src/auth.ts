import { createHash, timingSafeEqual } from "node:crypto";

import type { AuthContext } from "./types.js";

function splitList(value: string | undefined, fallback: string): string[] {
  return (value ?? fallback)
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean);
}

function sameSecret(left: string, right: string): boolean {
  const leftBytes = Buffer.from(left);
  const rightBytes = Buffer.from(right);

  return leftBytes.length === rightBytes.length && timingSafeEqual(leftBytes, rightBytes);
}

export function requireApiKey(apiKey: string | undefined, domain: string | undefined): AuthContext {
  const expected = process.env.WAT_API_KEY;
  if (!expected) {
    throw new Error("WAT_API_KEY is required");
  }
  if (!apiKey || !sameSecret(apiKey, expected)) {
    throw new Error("invalid api_key");
  }

  const domains = splitList(process.env.WAT_TEAM_DOMAINS, "example.com");
  const requestedDomain = domain?.trim().toLowerCase();
  if (requestedDomain && !domains.includes(requestedDomain)) {
    throw new Error("domain is outside api_key scope");
  }

  return {
    api_key_id: createHash("sha256").update(expected).digest("hex").slice(0, 12),
    domains,
    team_id: process.env.WAT_TEAM_ID ?? "team_example"
  };
}
