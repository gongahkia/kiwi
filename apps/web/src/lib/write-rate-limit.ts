import { authDb } from "@/lib/auth-db";

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

const testBuckets = new Map<string, Bucket>();

function useTestState(): boolean {
  return process.env.NODE_ENV === "test";
}

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

function resetAt(now: Date): Date {
  const next = new Date(now);
  next.setUTCDate(next.getUTCDate() + 1);
  next.setUTCHours(0, 0, 0, 0);
  return next;
}

export async function checkWriteRateLimit(
  action: WriteRateLimitAction,
  actorId: string,
  env: Record<string, string | undefined> = process.env,
  now = new Date()
): Promise<WriteRateLimitDecision> {
  const limit = limitFor(action, env);
  const key = `${action}:${actorId}`;
  const reset = resetAt(now);
  if (useTestState()) {
    const day = dayKey(now);
    const bucket = testBuckets.get(key);
    const current = bucket?.day === day ? bucket : { count: 0, day };
    if (current.count >= limit) {
      testBuckets.set(key, current);
      return { allowed: false, limit, remaining: 0, reset_at: reset.toISOString() };
    }
    current.count += 1;
    testBuckets.set(key, current);
    return {
      allowed: true,
      limit,
      remaining: Math.max(0, limit - current.count),
      reset_at: reset.toISOString()
    };
  }

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
    [key, action, reset, now]
  );
  const row = rows[0];
  if (!row) throw new Error("write rate limit upsert failed");
  return {
    allowed: row.count <= limit,
    limit,
    remaining: Math.max(0, limit - row.count),
    reset_at: row.reset_at.toISOString()
  };
}

export function resetWriteRateLimitsForTest(): void {
  testBuckets.clear();
}
