export type WriteRateLimitAction = "custom-entry" | "team-import";

export interface WriteRateLimitDecision {
  allowed: boolean;
  limit: number;
  remaining: number;
  reset_at: string;
}

interface Bucket {
  count: number;
  day: string;
}

const buckets = new Map<string, Bucket>();

function dayKey(now: Date): string {
  return now.toISOString().slice(0, 10);
}

function numberFromEnv(value: string | undefined, fallback: number): number {
  if (!value) return fallback;
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function limitFor(action: WriteRateLimitAction, env: Record<string, string | undefined>): number {
  if (action === "custom-entry") return numberFromEnv(env.WAT_CUSTOM_ENTRY_WRITE_LIMIT, 30);
  return numberFromEnv(env.WAT_IMPORT_WRITE_LIMIT, 5);
}

function resetAt(now: Date): string {
  const next = new Date(now);
  next.setUTCDate(next.getUTCDate() + 1);
  next.setUTCHours(0, 0, 0, 0);
  return next.toISOString();
}

export function checkWriteRateLimit(
  action: WriteRateLimitAction,
  actorId: string,
  env: Record<string, string | undefined> = process.env,
  now = new Date()
): WriteRateLimitDecision {
  const limit = limitFor(action, env);
  const key = `${action}:${actorId}`;
  const day = dayKey(now);
  const bucket = buckets.get(key);
  const current = bucket?.day === day ? bucket : { count: 0, day };

  if (current.count >= limit) {
    buckets.set(key, current);
    return { allowed: false, limit, remaining: 0, reset_at: resetAt(now) };
  }

  current.count += 1;
  buckets.set(key, current);
  return {
    allowed: true,
    limit,
    remaining: Math.max(0, limit - current.count),
    reset_at: resetAt(now)
  };
}

export function resetWriteRateLimitsForTest() {
  buckets.clear();
}
