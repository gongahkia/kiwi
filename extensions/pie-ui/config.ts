import { PERSONAS } from "./personas.ts";

export const PRESET_NAMES = [
	"minimal",
	"claude-inspired",
	"opencode-inspired",
	"codex-inspired",
	"gemini-inspired",
	"aider-inspired",
	"copilot-inspired",
	"cursor-inspired",
	"amp-inspired",
	"dracula",
	"tokyo-night",
	"catppuccin-mocha",
	"catppuccin-latte",
	"nord",
	"gruvbox-dark",
	"gruvbox-light",
] as const;
export const FOOTER_SEGMENTS = ["model", "thinking", "cwd", "branch", "status", "context", "tokens", "cost", "preset"] as const;
export const MODE_NAMES = ["full", "theme-only", "footer-only", "widgets-only"] as const;
export const WHEN_RULES = ["always", "git-repo", "trusted-project", "context>50", "context>70", "context>90", "tokens>10k"] as const;

export type PresetName = (typeof PRESET_NAMES)[number];
export type FooterSegment = (typeof FOOTER_SEGMENTS)[number];
export type PieMode = (typeof MODE_NAMES)[number];
export type WhenRule = (typeof WHEN_RULES)[number];
export type SegmentEntry = FooterSegment | { id: FooterSegment; when?: WhenRule };
export type PresetApplyMode = "clean" | "merge";
export type WidgetPlacement = "aboveEditor" | "belowEditor";

export type PieConfig = {
	preset?: PresetName;
	theme?: string;
	mode?: PieMode;
	compact?: boolean;
	strict?: boolean;
	persona?: string;
	header?: {
		enabled?: boolean;
		title?: string;
		subtitle?: string;
	};
	footer?: {
		enabled?: boolean;
		segments?: SegmentEntry[];
		separator?: string;
	};
	widget?: {
		enabled?: boolean;
		placement?: WidgetPlacement;
		lines?: string[];
	};
	tools?: {
		expanded?: boolean;
	};
	thinking?: {
		hiddenLabel?: string;
	};
	working?: {
		visible?: boolean;
		message?: string;
		frames?: string[];
		intervalMs?: number;
	};
};

export type ValidationResult = {
	valid: boolean;
	errors: string[];
	warnings: string[];
};

export const PRESET_THEMES: Record<PresetName, string> = {
	minimal: "fried-apple-pie-minimal",
	"claude-inspired": "fried-apple-pie-claude",
	"opencode-inspired": "fried-apple-pie-opencode",
	"codex-inspired": "fried-apple-pie-codex",
	"gemini-inspired": "fried-apple-pie-gemini",
	"aider-inspired": "fried-apple-pie-aider",
	"copilot-inspired": "fried-apple-pie-copilot",
	"cursor-inspired": "fried-apple-pie-cursor",
	"amp-inspired": "fried-apple-pie-amp",
	dracula: "fried-apple-pie-dracula",
	"tokyo-night": "fried-apple-pie-tokyo-night",
	"catppuccin-mocha": "fried-apple-pie-catppuccin-mocha",
	"catppuccin-latte": "fried-apple-pie-catppuccin-latte",
	nord: "fried-apple-pie-nord",
	"gruvbox-dark": "fried-apple-pie-gruvbox-dark",
	"gruvbox-light": "fried-apple-pie-gruvbox-light",
};

export const DEFAULT_CONFIG: PieConfig = {
	preset: "minimal",
	theme: PRESET_THEMES.minimal,
	mode: "full",
	compact: true,
	strict: false,
	header: {
		enabled: false,
		title: "Fried Apple Pie",
		subtitle: "Make Pi yours",
	},
	footer: {
		enabled: true,
		segments: ["model", "cwd", "branch", "status", "context"],
		separator: " · ",
	},
	widget: {
		enabled: false,
		placement: "aboveEditor",
		lines: [],
	},
	tools: {
		expanded: false,
	},
	thinking: {
		hiddenLabel: "thinking",
	},
	working: {
		visible: true,
		message: undefined,
		frames: undefined,
		intervalMs: undefined,
	},
};

export const PRESETS: Record<PresetName, PieConfig> = {
	minimal: {
		preset: "minimal",
		theme: PRESET_THEMES.minimal,
		compact: true,
		header: { enabled: false },
		footer: {
			enabled: true,
			segments: ["model", "cwd", "branch", "status", "context"],
			separator: " · ",
		},
		widget: { enabled: false },
		tools: { expanded: false },
		thinking: { hiddenLabel: "thinking" },
	},
	"claude-inspired": {
		preset: "claude-inspired",
		theme: PRESET_THEMES["claude-inspired"],
		compact: false,
		header: {
			enabled: true,
			title: "Fried Apple Pie",
			subtitle: "Claude-inspired preset",
		},
		footer: {
			enabled: true,
			segments: ["model", "thinking", "cwd", "branch", "status", "context"],
			separator: " · ",
		},
		widget: { enabled: false },
		tools: { expanded: false },
		thinking: { hiddenLabel: "thinking hidden" },
	},
	"opencode-inspired": {
		preset: "opencode-inspired",
		theme: PRESET_THEMES["opencode-inspired"],
		compact: true,
		header: { enabled: false },
		footer: {
			enabled: true,
			segments: ["cwd", "branch", "status", "model", "context"],
			separator: " | ",
		},
		widget: {
			enabled: true,
			placement: "aboveEditor",
			lines: ["Fried Apple Pie · tools compact · git visible · config editable"],
		},
		tools: { expanded: true },
		thinking: { hiddenLabel: "reasoning" },
	},
	"codex-inspired": {
		preset: "codex-inspired",
		theme: PRESET_THEMES["codex-inspired"],
		compact: true,
		header: {
			enabled: true,
			title: "Codex-inspired",
			subtitle: "dense agent workspace",
		},
		footer: {
			enabled: true,
			segments: ["model", "thinking", "cwd", "branch", "status", "context", "tokens"],
			separator: " · ",
		},
		widget: { enabled: false },
		tools: { expanded: false },
		thinking: { hiddenLabel: "reasoning" },
	},
	"gemini-inspired": {
		preset: "gemini-inspired",
		theme: PRESET_THEMES["gemini-inspired"],
		compact: false,
		header: {
			enabled: true,
			title: "Gemini-inspired",
			subtitle: "bright, high-contrast Pi",
		},
		footer: {
			enabled: true,
			segments: ["model", "context", "cwd", "branch", "status"],
			separator: "  ",
		},
		widget: {
			enabled: true,
			placement: "belowEditor",
			lines: ["preset: gemini-inspired · /pie preset minimal to switch back"],
		},
		tools: { expanded: true },
		thinking: { hiddenLabel: "thinking" },
	},
	"aider-inspired": {
		preset: "aider-inspired",
		theme: PRESET_THEMES["aider-inspired"],
		compact: true,
		header: { enabled: false },
		footer: {
			enabled: true,
			segments: ["model", "branch", "status"],
			separator: " ",
		},
		widget: { enabled: false },
		tools: { expanded: false },
		thinking: { hiddenLabel: "" },
	},
	"copilot-inspired": {
		preset: "copilot-inspired",
		theme: PRESET_THEMES["copilot-inspired"],
		compact: false,
		header: {
			enabled: true,
			title: "Copilot-inspired",
			subtitle: "dense Pi workspace",
		},
		footer: {
			enabled: true,
			segments: ["model", "thinking", "cwd", "branch", "status", "context", "tokens"],
			separator: " | ",
		},
		widget: { enabled: false },
		tools: { expanded: true },
		thinking: { hiddenLabel: "thinking" },
	},
	"cursor-inspired": {
		preset: "cursor-inspired",
		theme: PRESET_THEMES["cursor-inspired"],
		compact: true,
		header: { enabled: false },
		footer: {
			enabled: true,
			segments: ["model", "cwd", "branch", "status", "context"],
			separator: " · ",
		},
		widget: {
			enabled: true,
			placement: "aboveEditor",
			lines: ["preset: cursor-inspired · charcoal + electric blue"],
		},
		tools: { expanded: false },
		thinking: { hiddenLabel: "thinking" },
	},
	"amp-inspired": {
		preset: "amp-inspired",
		theme: PRESET_THEMES["amp-inspired"],
		compact: true,
		header: {
			enabled: true,
			title: "Amp-inspired",
			subtitle: "warm amber, compact tool pills",
		},
		footer: {
			enabled: true,
			segments: ["model", "thinking", "cwd", "branch", "status", "context"],
			separator: " · ",
		},
		widget: { enabled: false },
		tools: { expanded: true },
		thinking: { hiddenLabel: "reasoning" },
	},
	dracula: {
		preset: "dracula",
		theme: PRESET_THEMES.dracula,
		compact: true,
		header: { enabled: false },
		footer: {
			enabled: true,
			segments: ["model", "cwd", "branch", "status", "context"],
			separator: " · ",
		},
		widget: { enabled: false },
		tools: { expanded: false },
		thinking: { hiddenLabel: "thinking" },
	},
	"tokyo-night": {
		preset: "tokyo-night",
		theme: PRESET_THEMES["tokyo-night"],
		compact: true,
		header: { enabled: false },
		footer: {
			enabled: true,
			segments: ["model", "cwd", "branch", "status", "context"],
			separator: " · ",
		},
		widget: { enabled: false },
		tools: { expanded: false },
		thinking: { hiddenLabel: "thinking" },
	},
	"catppuccin-mocha": {
		preset: "catppuccin-mocha",
		theme: PRESET_THEMES["catppuccin-mocha"],
		compact: true,
		header: { enabled: false },
		footer: {
			enabled: true,
			segments: ["model", "cwd", "branch", "status", "context"],
			separator: " · ",
		},
		widget: { enabled: false },
		tools: { expanded: false },
		thinking: { hiddenLabel: "thinking" },
	},
	"catppuccin-latte": {
		preset: "catppuccin-latte",
		theme: PRESET_THEMES["catppuccin-latte"],
		compact: true,
		header: { enabled: false },
		footer: {
			enabled: true,
			segments: ["model", "cwd", "branch", "status", "context"],
			separator: " · ",
		},
		widget: { enabled: false },
		tools: { expanded: false },
		thinking: { hiddenLabel: "thinking" },
	},
	nord: {
		preset: "nord",
		theme: PRESET_THEMES.nord,
		compact: true,
		header: { enabled: false },
		footer: {
			enabled: true,
			segments: ["model", "cwd", "branch", "status", "context"],
			separator: " · ",
		},
		widget: { enabled: false },
		tools: { expanded: false },
		thinking: { hiddenLabel: "thinking" },
	},
	"gruvbox-dark": {
		preset: "gruvbox-dark",
		theme: PRESET_THEMES["gruvbox-dark"],
		compact: true,
		header: { enabled: false },
		footer: {
			enabled: true,
			segments: ["model", "cwd", "branch", "status", "context"],
			separator: " · ",
		},
		widget: { enabled: false },
		tools: { expanded: false },
		thinking: { hiddenLabel: "thinking" },
	},
	"gruvbox-light": {
		preset: "gruvbox-light",
		theme: PRESET_THEMES["gruvbox-light"],
		compact: true,
		header: { enabled: false },
		footer: {
			enabled: true,
			segments: ["model", "cwd", "branch", "status", "context"],
			separator: " · ",
		},
		widget: { enabled: false },
		tools: { expanded: false },
		thinking: { hiddenLabel: "thinking" },
	},
};

const objectKeys = new Set(["header", "footer", "widget", "tools", "thinking", "working"]);
const knownKeys = new Set(["preset", "theme", "mode", "compact", "strict", "persona", "header", "footer", "widget", "tools", "thinking", "working"]);
const presetNames = new Set<string>(PRESET_NAMES);
const footerSegments = new Set<string>(FOOTER_SEGMENTS);
const modeNames = new Set<string>(MODE_NAMES);
const whenRules = new Set<string>(WHEN_RULES);
const PERSONAS_KEYSET = new Set(Object.keys(PERSONAS));

export function isObject(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function cloneConfig<T>(value: T): T {
	if (value === undefined) return value;
	return JSON.parse(JSON.stringify(value)) as T;
}

export function mergeConfig(base: PieConfig, override: PieConfig | undefined): PieConfig {
	if (!override) return cloneConfig(base);
	const out = cloneConfig(base) as Record<string, unknown>;
	for (const [key, value] of Object.entries(override)) {
		if (value === undefined) continue;
		const current = out[key];
		if (objectKeys.has(key) && isObject(current) && isObject(value)) {
			out[key] = { ...current, ...value };
		} else {
			out[key] = cloneConfig(value);
		}
	}
	return out as PieConfig;
}

export function materializeConfig(raw: PieConfig | undefined): PieConfig {
	const basePreset = raw?.preset && presetNames.has(raw.preset) ? raw.preset : DEFAULT_CONFIG.preset ?? "minimal";
	return mergeConfig(mergeConfig(DEFAULT_CONFIG, PRESETS[basePreset]), raw);
}

export function effectiveConfig(globalConfig?: PieConfig, projectConfig?: PieConfig): PieConfig {
	return materializeConfig(mergeConfig(globalConfig ?? {}, projectConfig));
}

export function applyPresetConfig(config: PieConfig, preset: PresetName, applyMode: PresetApplyMode = "merge"): PieConfig {
	if (applyMode === "clean") {
		const preserved: PieConfig = {};
		if (config.mode !== undefined) preserved.mode = config.mode;
		if (config.strict !== undefined) preserved.strict = config.strict;
		return { ...preserved, preset, theme: PRESET_THEMES[preset] };
	}
	return { ...cloneConfig(config), preset, theme: PRESET_THEMES[preset] };
}

export function validateConfig(config: unknown, options: { strict?: boolean } = {}): ValidationResult {
	const errors: string[] = [];
	const warnings: string[] = [];
	if (!isObject(config)) {
		return { valid: false, errors: ["config must be an object"], warnings };
	}
	const strict = Boolean(options.strict || (config as PieConfig).strict);
	for (const key of Object.keys(config)) {
		if (!knownKeys.has(key)) {
			if (strict) errors.push(`unknown key: ${key}`);
			else warnings.push(`unknown key: ${key}`);
		}
	}
	const cfg = config as PieConfig;
	if (cfg.preset !== undefined && !presetNames.has(cfg.preset)) errors.push(`unknown preset: ${String(cfg.preset)}`);
	if (cfg.theme !== undefined && typeof cfg.theme !== "string") errors.push("theme must be a string");
	if (cfg.mode !== undefined && !modeNames.has(cfg.mode)) errors.push(`unknown mode: ${String(cfg.mode)}`);
	if (cfg.compact !== undefined && typeof cfg.compact !== "boolean") errors.push("compact must be a boolean");
	if (cfg.strict !== undefined && typeof cfg.strict !== "boolean") errors.push("strict must be a boolean");
	if (cfg.persona !== undefined) {
		if (typeof cfg.persona !== "string") errors.push("persona must be a string");
		else if (!PERSONAS_KEYSET.has(cfg.persona)) errors.push(`unknown persona: ${cfg.persona}`);
	}
	validateSection("header", cfg.header, errors, {
		enabled: "boolean",
		title: "string",
		subtitle: "string",
	});
	validateSection("footer", cfg.footer, errors, {
		enabled: "boolean",
		separator: "string",
	});
	if (cfg.footer?.segments !== undefined) {
		if (!Array.isArray(cfg.footer.segments)) {
			errors.push("footer.segments must be an array");
		} else {
			for (const segment of cfg.footer.segments) {
				if (typeof segment === "string") {
					if (!footerSegments.has(segment)) errors.push(`unknown footer segment: ${segment}`);
				} else if (isObject(segment)) {
					const id = (segment as { id?: unknown }).id;
					if (typeof id !== "string" || !footerSegments.has(id)) errors.push(`unknown footer segment: ${String(id)}`);
					const when = (segment as { when?: unknown }).when;
					if (when !== undefined && (typeof when !== "string" || !whenRules.has(when))) errors.push(`unknown footer segment when rule: ${String(when)}`);
				} else {
					errors.push(`footer segment must be a string or object: ${String(segment)}`);
				}
			}
		}
	}
	validateSection("widget", cfg.widget, errors, {
		enabled: "boolean",
		placement: "string",
	});
	if (cfg.widget?.placement !== undefined && cfg.widget.placement !== "aboveEditor" && cfg.widget.placement !== "belowEditor") {
		errors.push("widget.placement must be aboveEditor or belowEditor");
	}
	if (cfg.widget?.lines !== undefined && (!Array.isArray(cfg.widget.lines) || cfg.widget.lines.some((line) => typeof line !== "string"))) {
		errors.push("widget.lines must be an array of strings");
	}
	validateSection("tools", cfg.tools, errors, { expanded: "boolean" });
	validateSection("thinking", cfg.thinking, errors, { hiddenLabel: "string" });
	validateSection("working", cfg.working, errors, {
		visible: "boolean",
		message: "string",
		intervalMs: "number",
	});
	if (cfg.working?.frames !== undefined && (!Array.isArray(cfg.working.frames) || cfg.working.frames.some((frame) => typeof frame !== "string"))) {
		errors.push("working.frames must be an array of strings");
	}
	if (cfg.working?.intervalMs !== undefined && (!Number.isFinite(cfg.working.intervalMs) || cfg.working.intervalMs < 25)) {
		errors.push("working.intervalMs must be at least 25");
	}
	return { valid: errors.length === 0, errors, warnings };
}

function validateSection(name: string, value: unknown, errors: string[], fields: Record<string, "boolean" | "string" | "number">): void {
	if (value === undefined) return;
	if (!isObject(value)) {
		errors.push(`${name} must be an object`);
		return;
	}
	for (const [key, type] of Object.entries(fields)) {
		const child = value[key];
		if (child !== undefined && typeof child !== type) errors.push(`${name}.${key} must be a ${type}`);
	}
}

export type JsonPatchOperation = {
	op: "add" | "replace" | "remove";
	path: string;
	value?: unknown;
};

export function applyJsonPatch(config: PieConfig, operations: JsonPatchOperation[]): PieConfig {
	if (!Array.isArray(operations)) throw new Error("patch must be an array");
	let out = cloneConfig(config);
	for (const operation of operations) {
		out = applyOperation(out, operation);
	}
	return out;
}

function applyOperation(config: PieConfig, operation: JsonPatchOperation): PieConfig {
	if (!isObject(operation)) throw new Error("patch operation must be an object");
	if (operation.op !== "add" && operation.op !== "replace" && operation.op !== "remove") throw new Error(`unsupported patch op: ${String(operation.op)}`);
	if (typeof operation.path !== "string") throw new Error("patch path must be a string");
	if (operation.path === "") {
		if (operation.op === "remove") return {};
		if (!isObject(operation.value)) throw new Error("root replacement must be an object");
		return cloneConfig(operation.value as PieConfig);
	}
	const parts = parsePointer(operation.path);
	const out = cloneConfig(config) as Record<string, unknown>;
	const parent = resolveParent(out, parts);
	const key = parts[parts.length - 1];
	if (Array.isArray(parent)) {
		const index = key === "-" ? parent.length : Number(key);
		if (!Number.isInteger(index) || index < 0 || index > parent.length) throw new Error(`invalid array index: ${key}`);
		if (operation.op === "remove") {
			if (index >= parent.length) throw new Error(`patch path missing: ${operation.path}`);
			parent.splice(index, 1);
		} else if (operation.op === "add") {
			parent.splice(index, 0, cloneConfig(operation.value));
		} else {
			if (index >= parent.length) throw new Error(`patch path missing: ${operation.path}`);
			parent[index] = cloneConfig(operation.value);
		}
		return out as PieConfig;
	}
	if (!isObject(parent)) throw new Error(`patch parent is not an object: ${operation.path}`);
	if (operation.op === "remove") {
		if (!(key in parent)) throw new Error(`patch path missing: ${operation.path}`);
		delete parent[key];
	} else if (operation.op === "replace") {
		if (!(key in parent)) throw new Error(`patch path missing: ${operation.path}`);
		parent[key] = cloneConfig(operation.value);
	} else {
		parent[key] = cloneConfig(operation.value);
	}
	return out as PieConfig;
}

function parsePointer(path: string): string[] {
	if (!path.startsWith("/")) throw new Error(`patch path must start with /: ${path}`);
	return path
		.slice(1)
		.split("/")
		.map((part) => part.replace(/~1/g, "/").replace(/~0/g, "~"));
}

function resolveParent(root: Record<string, unknown>, parts: string[]): unknown {
	if (parts.length === 0) return root;
	let current: unknown = root;
	for (const part of parts.slice(0, -1)) {
		if (Array.isArray(current)) {
			const index = Number(part);
			if (!Number.isInteger(index) || index < 0 || index >= current.length) throw new Error(`patch path missing: /${parts.join("/")}`);
			current = current[index];
			continue;
		}
		if (!isObject(current) || !(part in current)) throw new Error(`patch path missing: /${parts.join("/")}`);
		current = current[part];
	}
	return current;
}
