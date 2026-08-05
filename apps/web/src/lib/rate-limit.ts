import { authDb } from "@/lib/auth-db";
import type { ApiIdentity } from "@/lib/api-identity";

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

export type RateLimitMemoryStore = Map<string, Bucket>;

const testBuckets: RateLimitMemoryStore = new Map();

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
    { key: `search:ip:${subject.ip}`, scope: "ip" }
  ];
  if (subject.identity.userId)
    keys.push({ key: `search:user:${subject.identity.userId}`, scope: "user" });
  if (subject.identity.teamId)
    keys.push({ key: `search:team:${subject.identity.teamId}`, scope: "team" });
  return keys;
}

function memoryDecision(
  key: string,
  scope: RateLimitScope,
  limit: number,
  windowMs: number,
  store: RateLimitMemoryStore,
  now: number
): RateLimitDecision {
  const existing = store.get(key);
  const bucket =
    existing && existing.resetAt > now ? existing : { count: 0, resetAt: now + windowMs };
  const count = bucket.count + 1;
  store.set(key, { count, resetAt: bucket.resetAt });
  return {
    allowed: count <= limit,
    limit,
    remaining: Math.max(0, limit - count),
    resetAt: bucket.resetAt,
    retryAfter: Math.max(1, Math.ceil((bucket.resetAt - now) / 1000)),
    scope
  };
}

async function dbDecision(
  key: string,
  scope: RateLimitScope,
  limit: number,
  windowMs: number,
  now: number
): Promise<RateLimitDecision> {
  const resetAt = new Date(now + windowMs);
  const { rows } = await authDb().query<{ count: number; reset_at: Date }>(
    `
    insert into rate_limit_buckets (key, scope, count, reset_at, updated_at)
    values ($1, $2, 1, $3, now())
    on conflict (key) do update
    set
      count = case
        when rate_limit_buckets.reset_at <= $4 then 1
        else rate_limit_buckets.count + 1
      end,
      reset_at = case
        when rate_limit_buckets.reset_at <= $4 then $3
        else rate_limit_buckets.reset_at
      end,
      updated_at = now()
    returning count, reset_at
    `,
    [key, scope, resetAt, new Date(now)]
  );
  const row = rows[0];
  if (!row) throw new Error("rate limit upsert failed");
  const resetMs = row.reset_at.getTime();
  return {
    allowed: row.count <= limit,
    limit,
    remaining: Math.max(0, limit - row.count),
    resetAt: resetMs,
    retryAfter: Math.max(1, Math.ceil((resetMs - now) / 1000)),
    scope
  };
}

export async function checkRateLimit(
  subject: RateLimitSubject,
  config: RateLimitConfig = rateLimitConfigFromEnv(),
  store: RateLimitMemoryStore | null = process.env.NODE_ENV === "test" ? testBuckets : null,
  now = Date.now()
): Promise<RateLimitDecision> {
  const keys = subjectKeys(subject);
  let tightest: RateLimitDecision | null = null;
  for (const { key, scope } of keys) {
    const decision = store
      ? memoryDecision(key, scope, config.limits[scope], config.windowMs, store, now)
      : await dbDecision(key, scope, config.limits[scope], config.windowMs, now);
    if (!tightest || decision.remaining < tightest.remaining) tightest = decision;
    if (!decision.allowed) return decision;
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

export function resetRateLimitsForTest(): void {
  testBuckets.clear();
}
