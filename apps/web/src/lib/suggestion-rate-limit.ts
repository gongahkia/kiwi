import { authDb } from "@/lib/auth-db";

export interface SuggestionRateLimitDecision {
  allowed: boolean;
  limit: number;
  remaining: number;
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

function resetAt(now: Date): Date {
  const next = new Date(now);
  next.setUTCDate(next.getUTCDate() + 1);
  next.setUTCHours(0, 0, 0, 0);
  return next;
}

export async function checkSuggestionRateLimit(
  actorId: string,
  limit = 10,
  now = new Date()
): Promise<SuggestionRateLimitDecision> {
  const key = `suggestion:${actorId}`;
  if (useTestState()) {
    const day = dayKey(now);
    const bucket = testBuckets.get(key);
    const current = bucket?.day === day ? bucket : { count: 0, day };
    if (current.count >= limit) {
      testBuckets.set(key, current);
      return { allowed: false, limit, remaining: 0 };
    }
    current.count += 1;
    testBuckets.set(key, current);
    return { allowed: true, limit, remaining: Math.max(0, limit - current.count) };
  }

  const { rows } = await authDb().query<{ count: number }>(
    `
    insert into rate_limit_buckets (key, scope, count, reset_at, updated_at)
    values ($1, 'suggestion', 1, $2, now())
    on conflict (key) do update
    set
      count = case
        when rate_limit_buckets.reset_at <= $3 then 1
        else rate_limit_buckets.count + 1
      end,
      reset_at = case
        when rate_limit_buckets.reset_at <= $3 then $2
        else rate_limit_buckets.reset_at
      end,
      updated_at = now()
    returning count
    `,
    [key, resetAt(now), now]
  );
  const count = rows[0]?.count ?? 0;
  return {
    allowed: count <= limit,
    limit,
    remaining: Math.max(0, limit - count)
  };
}

export function resetSuggestionRateLimitForTest(): void {
  testBuckets.clear();
}
