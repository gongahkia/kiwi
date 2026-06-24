import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type { PieConfig, ValidationResult } from "./config.ts";
import { effectiveConfig, isObject, validateConfig } from "./config.ts";

export type ConfigPaths = {
	globalPath: string;
	projectPath: string;
};

export type LoadedConfig = {
	paths: ConfigPaths;
	projectTrusted: boolean;
	globalConfig?: PieConfig;
	projectConfig?: PieConfig;
	effective: PieConfig;
	validation: ValidationResult;
	readErrors: string[];
};

export type ConfigScope = "global" | "project" | "effective";

export type WriteTarget = {
	path: string;
	scope: Exclude<ConfigScope, "effective">;
};

export function configPaths(cwd: string): ConfigPaths {
	return {
		globalPath: join(homedir(), ".pi", "agent", "pie-ui.json"),
		projectPath: join(cwd, ".pi", "pie-ui.json"),
	};
}

export function historyPath(): string {
	return join(homedir(), ".pi", "agent", "pie-history.json");
}

export type HistoryEntry = {
	ts: number;
	scope: "global" | "project";
	path: string;
	previous: PieConfig;
	next: PieConfig;
};

const HISTORY_CAP = 50;

export function readHistory(): HistoryEntry[] {
	const p = historyPath();
	if (!existsSync(p)) return [];
	try {
		const parsed = JSON.parse(readFileSync(p, "utf8"));
		if (!Array.isArray(parsed)) return [];
		return parsed.filter((entry): entry is HistoryEntry => entry && typeof entry.ts === "number" && entry.previous !== undefined && entry.next !== undefined);
	} catch {
		return [];
	}
}

export function appendHistory(entry: HistoryEntry): void {
	const entries = readHistory();
	entries.push(entry);
	while (entries.length > HISTORY_CAP) entries.shift();
	const p = historyPath();
	mkdirSync(dirname(p), { recursive: true });
	writeFileSync(p, `${JSON.stringify(entries, null, 2)}\n`, "utf8");
}

export function popHistory(): HistoryEntry | undefined {
	const entries = readHistory();
	const popped = entries.pop();
	if (!popped) return undefined;
	const p = historyPath();
	writeFileSync(p, `${JSON.stringify(entries, null, 2)}\n`, "utf8");
	return popped;
}

export function loadConfig(cwd: string, projectTrusted: boolean): LoadedConfig {
	const paths = configPaths(cwd);
	const readErrors: string[] = [];
	const globalConfig = readConfigFile(paths.globalPath, readErrors);
	const projectConfig = projectTrusted ? readConfigFile(paths.projectPath, readErrors) : undefined;
	const effective = effectiveConfig(globalConfig, projectConfig);
	const validation = validateConfig(effective);
	return { paths, projectTrusted, globalConfig, projectConfig, effective, validation, readErrors };
}

export function readConfigFile(path: string, readErrors: string[] = []): PieConfig | undefined {
	if (!existsSync(path)) return undefined;
	try {
		const parsed = JSON.parse(readFileSync(path, "utf8")) as unknown;
		if (!isObject(parsed)) {
			readErrors.push(`${path}: expected object`);
			return undefined;
		}
		const validation = validateConfig(parsed);
		if (!validation.valid) readErrors.push(`${path}: ${validation.errors.join("; ")}`);
		return parsed as PieConfig;
	} catch (error) {
		readErrors.push(`${path}: ${(error as Error).message}`);
		return undefined;
	}
}

export function writeConfigFile(path: string, config: PieConfig): void {
	mkdirSync(dirname(path), { recursive: true });
	writeFileSync(path, `${JSON.stringify(config, null, 2)}\n`, "utf8");
}

export function defaultWritePath(cwd: string, projectTrusted: boolean, scope?: "global" | "project" | "effective"): string {
	const paths = configPaths(cwd);
	if (scope === "global") return paths.globalPath;
	if (scope === "project") {
		if (!projectTrusted) return paths.globalPath;
		return paths.projectPath;
	}
	return projectTrusted ? paths.projectPath : paths.globalPath;
}

export function resolveWriteTarget(cwd: string, projectTrusted: boolean, scope?: ConfigScope): WriteTarget {
	const paths = configPaths(cwd);
	if (scope === "effective") throw new Error("effective scope is read-only; use dryRun or choose global/project");
	if (scope === "project") {
		if (!projectTrusted) throw new Error("project scope is unavailable until this project is trusted");
		return { path: paths.projectPath, scope: "project" };
	}
	if (scope === "global") return { path: paths.globalPath, scope: "global" };
	return projectTrusted ? { path: paths.projectPath, scope: "project" } : { path: paths.globalPath, scope: "global" };
}
