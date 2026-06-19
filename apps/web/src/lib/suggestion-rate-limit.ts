export interface SuggestionRateLimitDecision {
  allowed: boolean;
  limit: number;
  remaining: number;
}

interface Bucket {
  count: number;
  day: string;
}

const buckets = new Map<string, Bucket>();

function dayKey(now: Date): string {
  return now.toISOString().slice(0, 10);
}

export function checkSuggestionRateLimit(
  actorId: string,
  limit = 10,
  now = new Date()
): SuggestionRateLimitDecision {
  const day = dayKey(now);
  const bucket = buckets.get(actorId);
  const current = bucket?.day === day ? bucket : { count: 0, day };

  if (current.count >= limit) {
    buckets.set(actorId, current);
    return { allowed: false, limit, remaining: 0 };
  }

  current.count += 1;
  buckets.set(actorId, current);
  return { allowed: true, limit, remaining: Math.max(0, limit - current.count) };
}

export function resetSuggestionRateLimitForTest() {
  buckets.clear();
}
