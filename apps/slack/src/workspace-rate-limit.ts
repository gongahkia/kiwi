import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

export interface WorkspaceRateLimitConfig {
  channelLimit?: number;
  limit: number;
  userLimit?: number;
  windowMs: number;
  workspaceLimit?: number;
}

export interface WorkspaceRateLimitDecision {
  allowed: boolean;
  limit: number;
  remaining: number;
  resetAt: number;
  retryAfter: number;
  scope: SlackRateLimitScope;
  workspaceId: string;
}

interface Bucket {
  count: number;
  resetAt: number;
}

export type SlackRateLimitScope = "channel" | "user" | "workspace";

export interface SlackRateLimitSubject {
  channelId?: string;
  userId?: string;
  workspaceId: string;
}

export interface SlackRateLimitStore {
  get(key: string): Promise<Bucket | null>;
  set(key: string, bucket: Bucket): Promise<void>;
}

const buckets = new Map<string, Bucket>();

export class MemoryRateLimitStore implements SlackRateLimitStore {
  constructor(private readonly store = new Map<string, Bucket>()) {}

  async get(key: string): Promise<Bucket | null> {
    return this.store.get(key) ?? null;
  }

  async set(key: string, bucket: Bucket): Promise<void> {
    this.store.set(key, bucket);
  }
}

export class JsonFileRateLimitStore implements SlackRateLimitStore {
  constructor(private readonly filePath: string) {}

  async get(key: string): Promise<Bucket | null> {
    return (await this.read())[key] ?? null;
  }

  async set(key: string, bucket: Bucket): Promise<void> {
    const data = await this.read();
    data[key] = bucket;
    await mkdir(dirname(this.filePath), { recursive: true });
    const tempPath = `${this.filePath}.${process.pid}.tmp`;
    await writeFile(tempPath, JSON.stringify(data), "utf8");
    await rename(tempPath, this.filePath);
  }

  private async read(): Promise<Record<string, Bucket>> {
    try {
      return JSON.parse(await readFile(this.filePath, "utf8")) as Record<string, Bucket>;
    } catch (error) {
      if (error instanceof Error && "code" in error && error.code === "ENOENT") return {};
      throw error;
    }
  }
}

let defaultStore: SlackRateLimitStore | undefined;

export function defaultRateLimitStore(
  env: { SLACK_RATE_LIMIT_STORE_PATH?: string } = process.env
): SlackRateLimitStore {
  defaultStore ??= new JsonFileRateLimitStore(
    env.SLACK_RATE_LIMIT_STORE_PATH ?? ".wat-slack-rate-limits.json"
  );
  return defaultStore;
}

function numberFromEnv(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

export function workspaceRateLimitConfigFromEnv(
  env: {
    SLACK_CHANNEL_RATE_LIMIT?: string;
    SLACK_USER_RATE_LIMIT?: string;
    SLACK_WORKSPACE_RATE_LIMIT?: string;
    SLACK_WORKSPACE_RATE_LIMIT_WINDOW_MS?: string;
  } = process.env
): WorkspaceRateLimitConfig {
  return {
    channelLimit: numberFromEnv(env.SLACK_CHANNEL_RATE_LIMIT, 30),
    limit: numberFromEnv(env.SLACK_WORKSPACE_RATE_LIMIT, 30),
    userLimit: numberFromEnv(env.SLACK_USER_RATE_LIMIT, 30),
    workspaceLimit: numberFromEnv(env.SLACK_WORKSPACE_RATE_LIMIT, 30),
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
    scope: "workspace",
    workspaceId
  };
}

export async function checkSlackRateLimit(
  subject: SlackRateLimitSubject,
  config: WorkspaceRateLimitConfig = workspaceRateLimitConfigFromEnv(),
  store: SlackRateLimitStore = defaultRateLimitStore(),
  now = Date.now()
): Promise<WorkspaceRateLimitDecision> {
  if (!subject.workspaceId.trim()) {
    throw new Error("workspaceId is required");
  }

  const decisions: WorkspaceRateLimitDecision[] = [
    await checkBucket(
      "workspace",
      subject.workspaceId,
      subject.workspaceId,
      scopeLimit("workspace", config),
      config,
      store,
      now
    )
  ];
  if (subject.channelId) {
    decisions.push(
      await checkBucket(
        "channel",
        `${subject.workspaceId}:${subject.channelId}`,
        subject.workspaceId,
        scopeLimit("channel", config),
        config,
        store,
        now
      )
    );
  }
  if (subject.userId) {
    decisions.push(
      await checkBucket(
        "user",
        `${subject.workspaceId}:${subject.userId}`,
        subject.workspaceId,
        scopeLimit("user", config),
        config,
        store,
        now
      )
    );
  }

  return decisions.find((decision) => !decision.allowed) ?? decisions[0]!;
}

function scopeLimit(scope: SlackRateLimitScope, config: WorkspaceRateLimitConfig): number {
  if (scope === "channel") return config.channelLimit ?? config.limit;
  if (scope === "user") return config.userLimit ?? config.limit;
  return config.workspaceLimit ?? config.limit;
}

async function checkBucket(
  scope: SlackRateLimitScope,
  subjectId: string,
  workspaceId: string,
  limit: number,
  config: WorkspaceRateLimitConfig,
  store: SlackRateLimitStore,
  now: number
): Promise<WorkspaceRateLimitDecision> {
  const key = `${scope}:${subjectId}`;
  const existing = await store.get(key);
  const bucket =
    existing && existing.resetAt > now ? existing : { count: 0, resetAt: now + config.windowMs };
  const count = bucket.count + 1;
  await store.set(key, { count, resetAt: bucket.resetAt });

  return {
    allowed: count <= limit,
    limit,
    remaining: Math.max(0, limit - count),
    resetAt: bucket.resetAt,
    retryAfter: Math.max(1, Math.ceil((bucket.resetAt - now) / 1000)),
    scope,
    workspaceId
  };
}
