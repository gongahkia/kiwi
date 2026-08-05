import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

export interface SlackAutoDetectStore {
  isEnabled(workspaceId: string, channelId: string): Promise<boolean>;
  setEnabled(workspaceId: string, channelId: string, enabled: boolean): Promise<void>;
}

interface AutoDetectChannel {
  channelId: string;
  enabledAt: string;
  workspaceId: string;
}

export class MemorySlackAutoDetectStore implements SlackAutoDetectStore {
  private readonly channels = new Map<string, AutoDetectChannel>();

  async isEnabled(workspaceId: string, channelId: string): Promise<boolean> {
    return this.channels.has(channelKey(workspaceId, channelId));
  }

  async setEnabled(workspaceId: string, channelId: string, enabled: boolean): Promise<void> {
    const key = channelKey(workspaceId, channelId);
    if (!enabled) {
      this.channels.delete(key);
      return;
    }
    this.channels.set(key, {
      channelId,
      enabledAt: new Date().toISOString(),
      workspaceId
    });
  }
}

export class JsonFileSlackAutoDetectStore implements SlackAutoDetectStore {
  constructor(private readonly path: string) {}

  async isEnabled(workspaceId: string, channelId: string): Promise<boolean> {
    return (await this.readChannels()).has(channelKey(workspaceId, channelId));
  }

  async setEnabled(workspaceId: string, channelId: string, enabled: boolean): Promise<void> {
    const channels = await this.readChannels();
    const key = channelKey(workspaceId, channelId);
    if (enabled) {
      channels.set(key, { channelId, enabledAt: new Date().toISOString(), workspaceId });
    } else {
      channels.delete(key);
    }
    await this.writeChannels(channels);
  }

  private async readChannels(): Promise<Map<string, AutoDetectChannel>> {
    try {
      const body = JSON.parse(await readFile(this.path, "utf8")) as unknown;
      const channels =
        body && typeof body === "object" && Array.isArray((body as { channels?: unknown }).channels)
          ? (body as { channels: unknown[] }).channels
          : [];
      return new Map(
        channels
          .filter(isAutoDetectChannel)
          .map((channel) => [channelKey(channel.workspaceId, channel.channelId), channel])
      );
    } catch (error) {
      if (isNodeError(error) && error.code === "ENOENT") return new Map();
      throw error;
    }
  }

  private async writeChannels(channels: Map<string, AutoDetectChannel>): Promise<void> {
    await mkdir(dirname(this.path), { recursive: true });
    const tempPath = `${this.path}.${process.pid}.${Date.now()}.tmp`;
    const body = JSON.stringify(
      { channels: Array.from(channels.values()).sort(byWorkspaceChannel) },
      null,
      2
    );
    await writeFile(tempPath, `${body}\n`, "utf8");
    await rename(tempPath, this.path);
  }
}

function channelKey(workspaceId: string, channelId: string): string {
  return `${workspaceId}:${channelId}`;
}

function byWorkspaceChannel(left: AutoDetectChannel, right: AutoDetectChannel): number {
  return channelKey(left.workspaceId, left.channelId).localeCompare(
    channelKey(right.workspaceId, right.channelId)
  );
}

function isAutoDetectChannel(value: unknown): value is AutoDetectChannel {
  if (!value || typeof value !== "object") return false;
  const channel = value as Partial<AutoDetectChannel>;
  return (
    typeof channel.channelId === "string" &&
    typeof channel.enabledAt === "string" &&
    typeof channel.workspaceId === "string"
  );
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}
