import type { ApiIdentity } from "./api-identity";

export type RateLimitScope = "ip" | "team" | "user";

export interface RateLimitConfig {
  limits: Record<RateLimitScope, number>;
  windowMs: number;
}

export interface RateLimitSubject {
  identity: ApiIdentity;
  ip: string;
}

export interface RateLimitDecision {
  allowed: boolean;
  limit: number;
  remaining: number;
  resetAt: number;
  retryAfter: number;
  scope: RateLimitScope;
}

interface Bucket {
  count: number;
  resetAt: number;
}

const buckets = new Map<string, Bucket>();

interface RateLimitEnv {
  [key: string]: string | undefined;
  WAT_RATE_LIMIT_IP?: string;
  WAT_RATE_LIMIT_TEAM?: string;
  WAT_RATE_LIMIT_USER?: string;
  WAT_RATE_LIMIT_WINDOW_MS?: string;
}

function numberFromEnv(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

export function rateLimitConfigFromEnv(env: RateLimitEnv = process.env): RateLimitConfig {
  return {
    limits: {
      ip: numberFromEnv(env.WAT_RATE_LIMIT_IP, 60),
      team: numberFromEnv(env.WAT_RATE_LIMIT_TEAM, 300),
      user: numberFromEnv(env.WAT_RATE_LIMIT_USER, 120)
    },
    windowMs: numberFromEnv(env.WAT_RATE_LIMIT_WINDOW_MS, 60_000)
  };
}

function subjectKeys(subject: RateLimitSubject): Array<{ key: string; scope: RateLimitScope }> {
  const keys: Array<{ key: string; scope: RateLimitScope }> = [
    { key: `ip:${subject.ip}`, scope: "ip" }
  ];

  if (subject.identity.userId) {
    keys.push({ key: `user:${subject.identity.userId}`, scope: "user" });
  }
  if (subject.identity.teamId) {
    keys.push({ key: `team:${subject.identity.teamId}`, scope: "team" });
  }

  return keys;
}

export function checkRateLimit(
  subject: RateLimitSubject,
  config: RateLimitConfig = rateLimitConfigFromEnv(),
  store = buckets,
  now = Date.now()
): RateLimitDecision {
  const keys = subjectKeys(subject);
  let tightest: RateLimitDecision | null = null;

  for (const { key, scope } of keys) {
    const existing = store.get(key);
    const bucket =
      existing && existing.resetAt > now ? existing : { count: 0, resetAt: now + config.windowMs };
    const count = bucket.count + 1;
    store.set(key, { count, resetAt: bucket.resetAt });

    const limit = config.limits[scope];
    const remaining = Math.max(0, limit - count);
    const decision: RateLimitDecision = {
      allowed: count <= limit,
      limit,
      remaining,
      resetAt: bucket.resetAt,
      retryAfter: Math.max(1, Math.ceil((bucket.resetAt - now) / 1000)),
      scope
    };

    if (!tightest || decision.remaining < tightest.remaining) {
      tightest = decision;
    }
    if (!decision.allowed) {
      return decision;
    }
  }

  return (
    tightest ?? {
      allowed: true,
      limit: config.limits.ip,
      remaining: config.limits.ip,
      resetAt: now + config.windowMs,
      retryAfter: Math.ceil(config.windowMs / 1000),
      scope: "ip"
    }
  );
}
