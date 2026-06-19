export interface WorkspaceRateLimitConfig {
  limit: number;
  windowMs: number;
}

export interface WorkspaceRateLimitDecision {
  allowed: boolean;
  limit: number;
  remaining: number;
  resetAt: number;
  retryAfter: number;
  workspaceId: string;
}

interface Bucket {
  count: number;
  resetAt: number;
}

const buckets = new Map<string, Bucket>();

function numberFromEnv(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

export function workspaceRateLimitConfigFromEnv(
  env: {
    SLACK_WORKSPACE_RATE_LIMIT?: string;
    SLACK_WORKSPACE_RATE_LIMIT_WINDOW_MS?: string;
  } = process.env
): WorkspaceRateLimitConfig {
  return {
    limit: numberFromEnv(env.SLACK_WORKSPACE_RATE_LIMIT, 30),
    windowMs: numberFromEnv(env.SLACK_WORKSPACE_RATE_LIMIT_WINDOW_MS, 60_000)
  };
}

export function checkWorkspaceRateLimit(
  workspaceId: string,
  config: WorkspaceRateLimitConfig = workspaceRateLimitConfigFromEnv(),
  store = buckets,
  now = Date.now()
): WorkspaceRateLimitDecision {
  if (!workspaceId.trim()) {
    throw new Error("workspaceId is required");
  }

  const key = `workspace:${workspaceId}`;
  const existing = store.get(key);
  const bucket =
    existing && existing.resetAt > now ? existing : { count: 0, resetAt: now + config.windowMs };
  const count = bucket.count + 1;
  store.set(key, { count, resetAt: bucket.resetAt });

  return {
    allowed: count <= config.limit,
    limit: config.limit,
    remaining: Math.max(0, config.limit - count),
    resetAt: bucket.resetAt,
    retryAfter: Math.max(1, Math.ceil((bucket.resetAt - now) / 1000)),
    workspaceId
  };
}
