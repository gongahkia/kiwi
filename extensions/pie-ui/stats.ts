import { createHash } from "node:crypto";
import { homedir, hostname } from "node:os";
import { spawnSync } from "node:child_process";
import type { PieConfig } from "./config.ts";

export type PieStatsPayload = {
	preset?: string;
	persona?: string;
	layers: string[];
	hashedInstallId: string;
};

export type StatsPostResult = {
	sent: boolean;
	reason?: "disabled" | "missing-endpoint" | "missing-fetch" | "failed";
	status?: number;
};

type FetchLike = (input: string, init: { method: string; headers: Record<string, string>; body: string }) => Promise<{ ok: boolean; status: number }>;

export function analyticsStatus(config: PieConfig): string {
	if (!config.analytics?.enabled) return "analytics: disabled";
	return config.analytics.endpoint ? `analytics: enabled -> ${config.analytics.endpoint}` : "analytics: enabled, missing endpoint";
}

export function statsPayload(config: PieConfig, home = homedir(), machineId = readMachineId()): PieStatsPayload {
	return {
		preset: config.preset,
		persona: config.persona,
		layers: config.layers ?? [],
		hashedInstallId: hashedInstallId(home, machineId),
	};
}

export async function postStats(config: PieConfig, fetchImpl: FetchLike | undefined = globalThis.fetch as FetchLike | undefined, home?: string, machineId?: string): Promise<StatsPostResult> {
	if (!config.analytics?.enabled) return { sent: false, reason: "disabled" };
	const endpoint = config.analytics.endpoint?.trim();
	if (!endpoint) return { sent: false, reason: "missing-endpoint" };
	if (!fetchImpl) return { sent: false, reason: "missing-fetch" };
	try {
		const response = await fetchImpl(endpoint, {
			method: "POST",
			headers: { "content-type": "application/json" },
			body: JSON.stringify(statsPayload(config, home, machineId)),
		});
		return response.ok ? { sent: true, status: response.status } : { sent: false, reason: "failed", status: response.status };
	} catch {
		return { sent: false, reason: "failed" };
	}
}

export function hashedInstallId(home: string, machineId: string): string {
	return createHash("sha256").update(`${home}:${machineId}`).digest("hex").slice(0, 16);
}

function readMachineId(): string {
	const result = spawnSync("ioreg", ["-rd1", "-c", "IOPlatformExpertDevice"], { encoding: "utf8", timeout: 500 });
	const match = result.stdout?.match(/"IOPlatformUUID"\s=\s"([^"]+)"/);
	return match?.[1] ?? hostname();
}
