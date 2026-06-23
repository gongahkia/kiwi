import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
	applyJsonPatch,
	cloneConfig,
	type JsonPatchOperation,
	materializeConfig,
	type PieConfig,
	FOOTER_SEGMENTS,
	PRESET_NAMES,
	PRESET_THEMES,
	PRESETS,
	validateConfig,
} from "./config.ts";
import { defaultWritePath, loadConfig, readConfigFile, resolveWriteTarget, writeConfigFile } from "./paths.ts";
import { createFooter, createHeader, pickEditAction, pickPreset, type RenderState, showPanel, widgetLines } from "./render.ts";

const __dirname = dirname(fileURLToPath(import.meta.url));
const themeDir = resolve(__dirname, "../../themes");
const skillDir = resolve(__dirname, "../../skills");
const configToolSchema = Type.Object({
	action: Type.Union([
		Type.Literal("read"),
		Type.Literal("list_presets"),
		Type.Literal("validate"),
		Type.Literal("patch"),
		Type.Literal("apply"),
	]),
	scope: Type.Optional(Type.Union([Type.Literal("global"), Type.Literal("project"), Type.Literal("effective")])),
	config: Type.Optional(Type.Any()),
	patch: Type.Optional(
		Type.Array(
			Type.Object({
				op: Type.Union([Type.Literal("add"), Type.Literal("replace"), Type.Literal("remove")]),
				path: Type.String(),
				value: Type.Optional(Type.Any()),
			}),
		),
	),
	dryRun: Type.Optional(Type.Boolean()),
});

export default function (pi: ExtensionAPI) {
	const state: RenderState = { working: false };

	pi.on("resources_discover", () => ({
		themePaths: [themeDir],
		skillPaths: [skillDir],
	}));

	pi.on("session_start", (_event, ctx) => {
		applyPie(ctx, pi, state);
	});

	pi.on("agent_start", () => {
		state.working = true;
		state.requestRender?.();
	});

	pi.on("agent_end", () => {
		state.working = false;
		state.requestRender?.();
	});

	pi.on("model_select", () => state.requestRender?.());
	pi.on("thinking_level_select", () => state.requestRender?.());
	pi.on("message_end", () => state.requestRender?.());

	pi.registerCommand("pie", {
		description: "Switch and inspect Fried Apple Pie UI presets",
		getArgumentCompletions: (prefix) => {
			const parts = prefix.trimStart().split(/\s+/);
			if (parts.length <= 1) return ["preset", "edit", "welcome", "export", "show", "doctor", "reset"].filter((item) => item.startsWith(parts[0] ?? "")).map((item) => ({ label: item, value: item }));
			if (parts[0] === "preset") return PRESET_NAMES.filter((name) => name.startsWith(parts[1] ?? "")).map((name) => ({ label: name, value: `preset ${name}` }));
			return [];
		},
		handler: async (args, ctx) => {
			await handlePieCommand(args, ctx, pi, state);
		},
	});

	pi.registerTool({
		name: "pie_config",
		label: "Pie config",
		description: "Read, validate, patch, and apply Fried Apple Pie UI config.",
		promptSnippet: "Use pie_config to inspect or change Fried Apple Pie UI config.",
		promptGuidelines: [
			"Read the effective config before changing it.",
			"Use the supported JSON Patch subset for small config edits: add, replace, remove.",
			"Prefer presets unless the user asks for a custom layout.",
		],
		parameters: configToolSchema,
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			return runPieConfigTool(params as PieToolParams, ctx, pi, state);
		},
	});
}

type PieToolParams = {
	action: "read" | "list_presets" | "validate" | "patch" | "apply";
	scope?: "global" | "project" | "effective";
	config?: unknown;
	patch?: JsonPatchOperation[];
	dryRun?: boolean;
};

function applyPie(ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState): PieConfig {
	const loaded = loadConfig(ctx.cwd, ctx.isProjectTrusted());
	const config = loaded.effective;
	const validation = validateConfig(config);
	if (!validation.valid) {
		ctx.ui.notify(`Fried Apple Pie config invalid: ${validation.errors[0]}`, "error");
		return config;
	}
	if (config.theme) {
		const result = ctx.ui.setTheme(config.theme);
		if (!result.success) ctx.ui.notify(`Fried Apple Pie theme failed: ${result.error ?? config.theme}`, "warning");
	}
	ctx.ui.setToolsExpanded(Boolean(config.tools?.expanded));
	ctx.ui.setHiddenThinkingLabel(config.thinking?.hiddenLabel);
	ctx.ui.setWorkingVisible(config.working?.visible !== false);
	ctx.ui.setWorkingMessage(config.working?.message);
	ctx.ui.setWorkingIndicator(config.working?.frames ? { frames: config.working.frames, intervalMs: config.working.intervalMs } : undefined);
	const lines = widgetLines(config);
	ctx.ui.setWidget("fried-apple-pie", lines, { placement: config.widget?.placement ?? "aboveEditor" });
	if (ctx.mode === "tui") {
		ctx.ui.setHeader(config.header?.enabled === false ? undefined : (_tui, theme) => createHeader(config, theme));
		ctx.ui.setFooter(
			config.footer?.enabled === false
				? undefined
				: (tui, theme, footerData) => {
						state.requestRender = () => tui.requestRender();
						return createFooter(config, ctx, pi, state, theme, footerData);
					},
		);
	}
	return config;
}

async function handlePieCommand(args: string, ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState): Promise<void> {
	const [command, ...rest] = args.trim().split(/\s+/).filter(Boolean);
	const loaded = loadConfig(ctx.cwd, ctx.isProjectTrusted());
	if (!command) {
		const selected = await pickPreset(ctx, loaded.effective.preset);
		if (selected) await writePreset(selected, ctx, pi, state);
		return;
	}
	if (command === "preset") {
		const preset = rest[0];
		if (!PRESET_NAMES.includes(preset as (typeof PRESET_NAMES)[number])) {
			ctx.ui.notify(`Unknown preset: ${preset ?? ""}`, "error");
			return;
		}
		await writePreset(preset as (typeof PRESET_NAMES)[number], ctx, pi, state);
		return;
	}
	if (command === "show") {
		await showPanel(ctx, "Fried Apple Pie config", JSON.stringify(loaded, null, 2).split("\n"));
		return;
	}
	if (command === "edit") {
		await editConfig(ctx, pi, state);
		return;
	}
	if (command === "welcome") {
		await showPanel(ctx, "Fried Apple Pie", welcomeLines(loaded, ctx));
		return;
	}
	if (command === "export") {
		await showPanel(ctx, "Fried Apple Pie export", JSON.stringify(loaded.effective, null, 2).split("\n"));
		return;
	}
	if (command === "doctor") {
		await showPanel(ctx, "Fried Apple Pie doctor", doctorLines(loaded, ctx, pi));
		return;
	}
	if (command === "reset") {
		const path = defaultWritePath(ctx.cwd, ctx.isProjectTrusted());
		writeConfigFile(path, { preset: "minimal", theme: PRESET_THEMES.minimal });
		applyPie(ctx, pi, state);
		ctx.ui.notify(`Fried Apple Pie reset: ${path}`, "info");
		return;
	}
	ctx.ui.notify(`Unknown /pie command: ${command}`, "error");
}

async function writePreset(preset: (typeof PRESET_NAMES)[number], ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState): Promise<void> {
	const path = defaultWritePath(ctx.cwd, ctx.isProjectTrusted());
	const current = readConfigFile(path) ?? {};
	const next = { ...current, preset, theme: PRESET_THEMES[preset] };
	writeConfigFile(path, next);
	applyPie(ctx, pi, state);
	ctx.ui.notify(`Fried Apple Pie preset applied: ${preset}`, "info");
}

async function runPieConfigTool(params: PieToolParams, ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState) {
	const loaded = loadConfig(ctx.cwd, ctx.isProjectTrusted());
	if (params.action === "read") return toolResult("read", loaded);
	if (params.action === "list_presets") return toolResult("presets", presetDetails());
	if (params.action === "validate") {
		const target = params.config ?? loaded.effective;
		return toolResult("validate", validateConfig(target));
	}
	if (params.action === "patch") {
		if (!params.patch) throw new Error("patch action requires patch");
		if (params.scope === "effective" && !params.dryRun) return toolResult("patch rejected", { error: "effective scope is read-only; set dryRun true or choose global/project" }, true);
		const target = params.scope === "effective" ? undefined : resolveToolWriteTarget(ctx, params.scope);
		if (target && "error" in target) return toolResult("patch rejected", target, true);
		const current = target ? (readConfigFile(target.path) ?? {}) : loaded.effective;
		const next = applyJsonPatch(current, params.patch);
		const validation = validateConfig(materializeConfig(next));
		if (!validation.valid) return toolResult("patch rejected", validation, true);
		if (!params.dryRun && target) {
			writeConfigFile(target.path, next);
			applyPie(ctx, pi, state);
		}
		return toolResult("patch", { path: target?.path, scope: params.scope ?? target?.scope ?? "effective", writable: Boolean(target), dryRun: Boolean(params.dryRun || !target), config: next, validation });
	}
	if (params.action === "apply") {
		if (!params.config) {
			const config = applyPie(ctx, pi, state);
			return toolResult("applied current config", { config });
		}
		const candidate = cloneConfig(params.config as PieConfig);
		const validation = validateConfig(materializeConfig(candidate));
		if (!validation.valid) return toolResult("apply rejected", validation, true);
		if (params.scope === "effective" && !params.dryRun) return toolResult("apply rejected", { error: "effective scope is read-only; set dryRun true or choose global/project" }, true);
		const target = params.scope === "effective" ? undefined : resolveToolWriteTarget(ctx, params.scope);
		if (target && "error" in target) return toolResult("apply rejected", target, true);
		if (!params.dryRun && target) {
			writeConfigFile(target.path, candidate);
			applyPie(ctx, pi, state);
		}
		return toolResult("apply", { path: target?.path, scope: params.scope ?? target?.scope ?? "effective", writable: Boolean(target), dryRun: Boolean(params.dryRun || !target), config: candidate, validation });
	}
	throw new Error(`unknown action: ${(params as { action: string }).action}`);
}

async function editConfig(ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState): Promise<void> {
	const loaded = loadConfig(ctx.cwd, ctx.isProjectTrusted());
	const action = await pickEditAction(ctx, loaded.effective);
	if (!action || action === "cancel") return;
	const path = defaultWritePath(ctx.cwd, ctx.isProjectTrusted());
	const current = readConfigFile(path) ?? {};
	const next = cloneConfig(current);
	if (action === "preset") {
		const preset = await pickPreset(ctx, loaded.effective.preset);
		if (!preset) return;
		next.preset = preset;
		next.theme = PRESET_THEMES[preset];
	}
	if (action === "theme") {
		const names = ctx.ui.getAllThemes().map((theme) => theme.name).sort();
		const selected = await ctx.ui.select("Fried Apple Pie theme", names);
		if (!selected) return;
		next.theme = selected;
	}
	if (action === "compact") next.compact = !Boolean(loaded.effective.compact);
	if (action === "footer") {
		const value = await ctx.ui.input("Footer segments", loaded.effective.footer?.segments?.join(",") ?? "");
		if (value === undefined) return;
		const segments = value.split(",").map((segment) => segment.trim()).filter(Boolean);
		const invalid = segments.filter((segment) => !FOOTER_SEGMENTS.includes(segment as (typeof FOOTER_SEGMENTS)[number]));
		if (invalid.length > 0) {
			ctx.ui.notify(`Invalid footer segment: ${invalid[0]}`, "error");
			return;
		}
		next.footer = { ...next.footer, enabled: true, segments: segments as PieConfig["footer"]["segments"] };
	}
	if (action === "header") next.header = { ...next.header, enabled: loaded.effective.header?.enabled === false };
	if (action === "widget") {
		const enabled = !Boolean(loaded.effective.widget?.enabled);
		const line = enabled ? await ctx.ui.input("Widget text", loaded.effective.widget?.lines?.[0] ?? "Fried Apple Pie · config editable") : undefined;
		if (enabled && line === undefined) return;
		next.widget = { ...next.widget, enabled, lines: enabled ? [line ?? ""] : next.widget?.lines };
	}
	if (action === "tools") next.tools = { ...next.tools, expanded: !Boolean(loaded.effective.tools?.expanded) };
	const validation = validateConfig(materializeConfig(next));
	if (!validation.valid) {
		ctx.ui.notify(`Invalid config: ${validation.errors[0]}`, "error");
		return;
	}
	writeConfigFile(path, next);
	applyPie(ctx, pi, state);
	ctx.ui.notify(`Fried Apple Pie updated: ${action}`, "info");
}

function resolveToolWriteTarget(ctx: ExtensionContext, scope: PieToolParams["scope"]): ReturnType<typeof resolveWriteTarget> | { error: string } {
	try {
		return resolveWriteTarget(ctx.cwd, ctx.isProjectTrusted(), scope);
	} catch (error) {
		return { error: (error as Error).message };
	}
}

function toolResult(label: string, details: unknown, isError = false) {
	return {
		content: [{ type: "text" as const, text: `${label}\n${JSON.stringify(details, null, 2)}` }],
		details,
		isError,
	};
}

function presetDetails(): Record<string, PieConfig> {
	return Object.fromEntries(PRESET_NAMES.map((name) => [name, PRESETS[name]]));
}

function welcomeLines(loaded: ReturnType<typeof loadConfig>, ctx: ExtensionContext): string[] {
	return [
		`preset: ${loaded.effective.preset ?? "custom"}`,
		`theme: ${loaded.effective.theme ?? "default"}`,
		`model: ${ctx.model?.id ?? "no-model"}`,
		`cwd: ${ctx.cwd}`,
		`config: ${loaded.projectTrusted ? loaded.paths.projectPath : loaded.paths.globalPath}`,
		"",
		"/pie edit     configure preset, theme, footer, header, widget, tools",
		"/pie export   show effective config",
		"/pie doctor   validate config and conflicts",
		"/pie reset    return to minimal preset",
	];
}

function doctorLines(loaded: ReturnType<typeof loadConfig>, ctx: ExtensionContext, pi: ExtensionAPI): string[] {
	const lines: string[] = [];
	lines.push(`global: ${loaded.paths.globalPath}`);
	lines.push(`project: ${loaded.paths.projectPath}`);
	lines.push(`project trusted: ${loaded.projectTrusted ? "yes" : "no"}`);
	lines.push(`active preset: ${loaded.effective.preset ?? "custom"}`);
	lines.push(`active theme: ${loaded.effective.theme ?? "default"}`);
	for (const error of loaded.readErrors) lines.push(`read error: ${error}`);
	for (const error of loaded.validation.errors) lines.push(`config error: ${error}`);
	for (const warning of loaded.validation.warnings) lines.push(`config warning: ${warning}`);
	const themes = new Set(ctx.ui.getAllThemes().map((theme) => theme.name));
	if (loaded.effective.theme && !themes.has(loaded.effective.theme)) lines.push(`theme unavailable: ${loaded.effective.theme}`);
	const commands = pi.getCommands().map((command) => command.name);
	const conflicts = commands.filter((name) => ["footer", "powerline-footer", "tool-display"].includes(name));
	for (const conflict of conflicts) lines.push(`possible UI conflict: /${conflict}`);
	if (lines.length === 5) lines.push("ok");
	return lines;
}
