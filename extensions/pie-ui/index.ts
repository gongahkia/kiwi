import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
	applyJsonPatch,
	applyPresetConfig,
	cloneConfig,
	type FooterSegment,
	type JsonPatchOperation,
	materializeConfig,
	MODE_NAMES,
	type PieConfig,
	type PieMode,
	type PresetName,
	type PresetApplyMode,
	FOOTER_SEGMENTS,
	PRESET_NAMES,
	PRESET_THEMES,
	PRESETS,
	validateConfig,
} from "./config.ts";
import { appendHistory, defaultWritePath, type HistoryEntry, loadConfig, popHistory, readConfigFile, readHistory, resolveWriteTarget, writeConfigFile } from "./paths.ts";
import { PERSONA_NAMES, PERSONAS, resolvePersona, SPINNERS } from "./personas.ts";
import { createFooter, createHeader, pickEditAction, pickFooterSegments, pickGallery, pickPreset, type RenderState, showPanel, widgetLines } from "./render.ts";

const __dirname = dirname(fileURLToPath(import.meta.url));
const themeDir = resolve(__dirname, "../../themes");
const skillDir = resolve(__dirname, "../../skills");
const tapesDir = resolve(__dirname, "../../assets/tapes");
const configToolSchema = Type.Object({
	action: Type.Union([
		Type.Literal("read"),
		Type.Literal("list_presets"),
		Type.Literal("validate"),
		Type.Literal("patch"),
		Type.Literal("apply"),
		Type.Literal("set_preset"),
		Type.Literal("set_footer_segments"),
		Type.Literal("toggle_compact"),
		Type.Literal("set_theme"),
	]),
	scope: Type.Optional(Type.Union([Type.Literal("global"), Type.Literal("project"), Type.Literal("effective")])),
	config: Type.Optional(Type.Any()),
	preset: Type.Optional(Type.Union(PRESET_NAMES.map((name) => Type.Literal(name)))),
	theme: Type.Optional(Type.String()),
	footerSegments: Type.Optional(Type.Array(Type.Union(FOOTER_SEGMENTS.map((name) => Type.Literal(name))))),
	applyMode: Type.Optional(Type.Union([Type.Literal("clean"), Type.Literal("merge")])),
	strict: Type.Optional(Type.Boolean()),
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
	// context-warning latch: fire each threshold at most once per session; cleared on /compact.
	const warned: { mid: boolean; high: boolean } = { mid: false, high: false };

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

	pi.on("turn_start", (_event, ctx) => {
		rotateWorkingVerb(ctx, state);
	});

	pi.on("model_select", () => state.requestRender?.());
	pi.on("thinking_level_select", () => state.requestRender?.());
	pi.on("message_end", (_event, ctx) => {
		state.requestRender?.();
		if (state.lastConfig?.mode === "status-only") refreshStatusFromState(ctx, state);
		maybeWarnContext(ctx, state, warned);
	});
	// session_compact may not fire on every Pi build; subscription is defensive.
	pi.on("session_compact", () => {
		warned.mid = false;
		warned.high = false;
	});

	pi.registerCommand("pie", {
		description: "Switch and inspect Fried Apple Pie UI presets",
		getArgumentCompletions: (prefix) => {
			const parts = prefix.trimStart().split(/\s+/);
			if (parts.length <= 1) return ["preset", "mode", "persona", "gallery", "diff", "history", "undo", "import", "capture", "edit", "welcome", "export", "show", "doctor", "reset"].filter((item) => item.startsWith(parts[0] ?? "")).map((item) => ({ label: item, value: item }));
			if (parts[0] === "preset") return PRESET_NAMES.filter((name) => name.startsWith(parts[1] ?? "")).map((name) => ({ label: name, value: `preset ${name}` }));
			if (parts[0] === "mode") return MODE_NAMES.filter((name) => name.startsWith(parts[1] ?? "")).map((name) => ({ label: name, value: `mode ${name}` }));
			if (parts[0] === "persona") return PERSONA_NAMES.filter((name) => name.startsWith(parts[1] ?? "")).map((name) => ({ label: name, value: `persona ${name}` }));
			if (parts[0] === "diff") return PRESET_NAMES.filter((name) => name.startsWith(parts[1] ?? "")).map((name) => ({ label: name, value: `diff ${name}` }));
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
	action: "read" | "list_presets" | "validate" | "patch" | "apply" | "set_preset" | "set_footer_segments" | "toggle_compact" | "set_theme";
	scope?: "global" | "project" | "effective";
	config?: unknown;
	preset?: PresetName;
	theme?: string;
	footerSegments?: FooterSegment[];
	applyMode?: PresetApplyMode;
	strict?: boolean;
	patch?: JsonPatchOperation[];
	dryRun?: boolean;
};

export function applyPie(ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState): PieConfig {
	const loaded = loadConfig(ctx.cwd, ctx.isProjectTrusted());
	return applyEffectiveConfig(ctx, pi, state, loaded.effective);
}

// applies an already-materialized config directly. used by applyPie (live config) and /pie gallery (transient cycle).
export function applyEffectiveConfig(ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState, config: PieConfig): PieConfig {
	const validation = validateConfig(config);
	if (!validation.valid) {
		ctx.ui.notify(`Fried Apple Pie config invalid: ${validation.errors[0]}`, "error");
		return config;
	}
	if (config.theme) {
		const result = ctx.ui.setTheme(config.theme);
		if (!result.success) ctx.ui.notify(`Fried Apple Pie theme failed: ${result.error ?? config.theme}`, "warning");
	}
	const mode = config.mode ?? "full";
	if (mode === "full") {
		ctx.ui.setToolsExpanded(Boolean(config.tools?.expanded));
		ctx.ui.setHiddenThinkingLabel(config.thinking?.hiddenLabel);
		ctx.ui.setWorkingVisible(config.working?.visible !== false);
		// persona drives spinner+verb when not explicitly overridden in working.frames / working.message
		const persona = resolvePersona(config.persona, config.preset);
		const frames = config.working?.frames ?? (persona ? SPINNERS[persona.spinner].frames : undefined);
		const intervalMs = config.working?.intervalMs ?? (persona ? SPINNERS[persona.spinner].intervalMs : undefined);
		const message = config.working?.message ?? persona?.verbs[0];
		ctx.ui.setWorkingMessage(message);
		ctx.ui.setWorkingIndicator(frames ? { frames, intervalMs } : undefined);
		state.verbKey = persona ? personaVerbKey(config, persona) : undefined;
		state.verbIndex = config.working?.message === undefined && persona?.verbs.length ? 1 % persona.verbs.length : 0;
	} else {
		ctx.ui.setToolsExpanded(false);
		ctx.ui.setHiddenThinkingLabel();
		ctx.ui.setWorkingMessage();
		ctx.ui.setWorkingIndicator();
		ctx.ui.setWorkingVisible(true);
		state.verbKey = undefined;
		state.verbIndex = 0;
	}
	const ownsWidgets = mode === "full" || mode === "widgets-only";
	const lines = ownsWidgets ? widgetLines(config) : undefined;
	ctx.ui.setWidget("fried-apple-pie", lines, { placement: config.widget?.placement ?? "aboveEditor" });
	if (ctx.mode === "tui") {
		ctx.ui.setHeader(ownsWidgets ? (config.header?.enabled === false ? undefined : (_tui, theme) => createHeader(config, theme)) : undefined);
		ctx.ui.setFooter(
			(mode === "full" || mode === "footer-only") && config.footer?.enabled !== false
				? (tui, theme, footerData) => {
						state.requestRender = () => tui.requestRender();
						return createFooter(config, ctx, pi, state, theme, footerData);
					}
				: undefined,
		);
	}
	// status-only mode: write a small secondary surface instead of owning header/footer/widget.
	// other modes clear the key so a previous status-only session does not leak text.
	refreshStatus(ctx, mode === "status-only" ? config : undefined);
	state.lastConfig = config;
	return config;
}

// computes the small status text used in status-only mode. uses contextLeft for compactness.
export function pieStatusText(config: PieConfig, ctx: ExtensionContext): string {
	const usage = ctx.getContextUsage();
	const left = usage?.percent != null ? `ctx ${Math.max(0, Math.min(100, Math.round(100 - usage.percent)))}%` : "";
	const persona = config.persona ? `${config.persona}` : "";
	return [config.preset ?? "custom", persona, left].filter(Boolean).join(" · ");
}

// writes or clears the secondary status. ctx.ui.setStatus may be absent on older Pi builds; optional-chain guards.
function refreshStatus(ctx: ExtensionContext, config: PieConfig | undefined): void {
	const setStatus = (ctx.ui as unknown as { setStatus?: (key: string, text?: string) => void }).setStatus;
	if (!setStatus) return;
	if (config) setStatus("fried-apple-pie", pieStatusText(config, ctx));
	else setStatus("fried-apple-pie");
}

// re-applies status text from the last-applied config without re-running the full pipeline. used on message_end.
function refreshStatusFromState(ctx: ExtensionContext, state: RenderState): void {
	if (!state.lastConfig) return;
	refreshStatus(ctx, state.lastConfig);
}

// fires opt-out-able warnings when context usage crosses 70% / 90% thresholds. one-shot per session per threshold.
export function maybeWarnContext(ctx: ExtensionContext, state: RenderState, warned: { mid: boolean; high: boolean }): void {
	if (state.lastConfig?.notifications?.contextWarnings === false) return;
	const usage = ctx.getContextUsage();
	if (!usage || usage.percent == null) return;
	const pct = usage.percent;
	if (pct >= 90 && !warned.high) {
		ctx.ui.notify("Fried Apple Pie: context >90%. Consider /compact.", "warning");
		warned.high = true;
	} else if (pct >= 70 && !warned.mid) {
		ctx.ui.notify("Fried Apple Pie: context >70%.", "info");
		warned.mid = true;
	}
}

export function rotateWorkingVerb(ctx: ExtensionContext, state: RenderState): string | undefined {
	const config = state.lastConfig;
	if (!config || (config.mode ?? "full") !== "full" || config.working?.message !== undefined) return undefined;
	const persona = resolvePersona(config.persona, config.preset);
	if (!persona?.verbs.length) return undefined;
	const key = personaVerbKey(config, persona);
	if (state.verbKey !== key) {
		state.verbKey = key;
		state.verbIndex = 0;
	}
	const index = state.verbIndex ?? 0;
	const message = persona.verbs[index % persona.verbs.length];
	state.verbIndex = (index + 1) % persona.verbs.length;
	ctx.ui.setWorkingMessage(message);
	state.requestRender?.();
	return message;
}

function personaVerbKey(config: PieConfig, persona: { spinner: string; verbs: string[] }): string {
	return [config.preset ?? "", config.persona ?? "", persona.spinner, ...persona.verbs].join("\u0000");
}

async function handlePieCommand(args: string, ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState): Promise<void> {
	const [command, ...rest] = args.trim().split(/\s+/).filter(Boolean);
	const loaded = loadConfig(ctx.cwd, ctx.isProjectTrusted());
	if (!command) {
		const selected = await pickPreset(ctx, loaded.effective.preset);
		if (selected) await writePreset(selected, ctx, pi, state, "clean");
		return;
	}
	if (command === "preset") {
		const preset = rest[0];
		if (!PRESET_NAMES.includes(preset as (typeof PRESET_NAMES)[number])) {
			ctx.ui.notify(`Unknown preset: ${preset ?? ""}`, "error");
			return;
		}
		await writePreset(preset as (typeof PRESET_NAMES)[number], ctx, pi, state, rest[1] === "merge" ? "merge" : "clean");
		return;
	}
	if (command === "mode") {
		const mode = rest[0];
		if (!MODE_NAMES.includes(mode as PieMode)) {
			ctx.ui.notify(`Unknown mode: ${mode ?? ""}`, "error");
			return;
		}
		await writeMode(mode as PieMode, ctx, pi, state);
		return;
	}
	if (command === "persona") {
		const persona = rest[0];
		if (!persona || !PERSONAS[persona]) {
			ctx.ui.notify(`Unknown persona: ${persona ?? ""}`, "error");
			return;
		}
		await writePersona(persona, ctx, pi, state);
		return;
	}
	if (command === "gallery") {
		await runGallery(ctx, pi, state, loaded.effective);
		return;
	}
	if (command === "diff") {
		const target = rest[0];
		if (!PRESET_NAMES.includes(target as PresetName)) {
			ctx.ui.notify(`Unknown preset: ${target ?? ""}`, "error");
			return;
		}
		const before = loaded.effective;
		const after = materializeConfig(applyPresetConfig(before, target as PresetName, rest[1] === "merge" ? "merge" : "clean"));
		await showPanel(ctx, `Fried Apple Pie diff: ${before.preset ?? "custom"} -> ${target}`, diffLines(before, after));
		return;
	}
	if (command === "history") {
		await showPanel(ctx, "Fried Apple Pie history", historyLines(readHistory()));
		return;
	}
	if (command === "undo") {
		const popped = popHistory();
		if (!popped) {
			ctx.ui.notify("Fried Apple Pie history is empty", "warning");
			return;
		}
		writeConfigFile(popped.path, popped.previous);
		applyPie(ctx, pi, state);
		const label = popped.previous.preset ?? "custom";
		ctx.ui.notify(`Fried Apple Pie undo: restored ${label} at ${popped.path}`, "info");
		return;
	}
	if (command === "import") {
		await importConfig(rest.join(" "), ctx, pi, state);
		return;
	}
	if (command === "capture") {
		await runCapture(loaded.effective.preset, ctx, pi);
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
		await showPanel(ctx, "Fried Apple Pie doctor", doctorLines(loaded, ctx, pi, rest[0] === "strict"));
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

async function writePreset(preset: PresetName, ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState, applyMode: PresetApplyMode): Promise<void> {
	const path = defaultWritePath(ctx.cwd, ctx.isProjectTrusted());
	const current = readConfigFile(path) ?? {};
	const next = applyPresetConfig(current, preset, applyMode);
	const scope = ctx.isProjectTrusted() ? "project" : "global";
	const ts = Date.now();
	appendHistory({ ts, scope, path, previous: current, next });
	writeConfigFile(path, next);
	applyPie(ctx, pi, state);
	emitPieEvent(pi, "pie:preset-changed", { from: current.preset, to: preset, scope, path, ts });
	ctx.ui.notify(`Fried Apple Pie preset applied: ${preset} (${applyMode})`, "info");
}

async function writeMode(mode: PieMode, ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState): Promise<void> {
	const path = defaultWritePath(ctx.cwd, ctx.isProjectTrusted());
	const current = readConfigFile(path) ?? {};
	const scope = ctx.isProjectTrusted() ? "project" : "global";
	const ts = Date.now();
	writeConfigFile(path, { ...current, mode });
	applyPie(ctx, pi, state);
	emitPieEvent(pi, "pie:mode-changed", { from: current.mode, to: mode, scope, path, ts });
	ctx.ui.notify(`Fried Apple Pie mode applied: ${mode}`, "info");
}

async function writePersona(persona: string, ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState): Promise<void> {
	const path = defaultWritePath(ctx.cwd, ctx.isProjectTrusted());
	const current = readConfigFile(path) ?? {};
	const scope = ctx.isProjectTrusted() ? "project" : "global";
	const ts = Date.now();
	writeConfigFile(path, { ...current, persona });
	applyPie(ctx, pi, state);
	emitPieEvent(pi, "pie:persona-changed", { from: current.persona, to: persona, scope, path, ts });
	ctx.ui.notify(`Fried Apple Pie persona applied: ${persona}`, "info");
}

// emits a pie:* event on the Pi inter-extension bus. defensive optional-chain tolerates older builds.
export function emitPieEvent(pi: ExtensionAPI, name: string, payload: { from?: string; to?: string; scope: "global" | "project"; path: string; ts: number }): void {
	const events = (pi as unknown as { events?: { emit?: (name: string, payload: unknown) => void } }).events;
	events?.emit?.(name, payload);
}

// resolves the tape path for a preset. exported for tests.
export function tapePathFor(preset: PresetName | undefined): string {
	return resolve(tapesDir, `${preset ?? "minimal"}.tape`);
}

// /pie capture: shells out to vhs for the active preset's tape. requires vhs+ttyd+ffmpeg on PATH.
async function runCapture(preset: PresetName | undefined, ctx: ExtensionContext, pi: ExtensionAPI): Promise<void> {
	const tape = tapePathFor(preset);
	if (!existsSync(tape)) {
		ctx.ui.notify(`Fried Apple Pie capture: no tape at ${tape}. Run npm run assets:tapes to regenerate.`, "error");
		return;
	}
	const exec = (pi as unknown as { exec?: (cmd: string, args: string[], opts?: { signal?: AbortSignal }) => Promise<unknown> }).exec;
	if (!exec) {
		ctx.ui.notify("Fried Apple Pie capture: pi.exec unavailable on this build. Run scripts/capture.sh from a shell.", "warning");
		return;
	}
	ctx.ui.notify(`Fried Apple Pie capture: rendering ${tape} (requires vhs/ttyd/ffmpeg on PATH)…`, "info");
	try {
		await exec("vhs", [tape], { signal: ctx.signal });
		ctx.ui.notify(`Fried Apple Pie capture: wrote assets/preview-${preset}.gif`, "info");
	} catch (error) {
		ctx.ui.notify(`Fried Apple Pie capture failed: ${(error as Error).message}`, "error");
	}
}

// /pie gallery: live-cycle every preset in-memory without writing to disk. on q/esc restores snapshot.
// returns immediately on non-tui modes.
async function runGallery(ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState, snapshot: PieConfig): Promise<void> {
	if (ctx.mode !== "tui") {
		ctx.ui.notify("Fried Apple Pie gallery requires TUI mode", "warning");
		return;
	}
	const apply = (preset: PresetName) => {
		const transient = materializeConfig(applyPresetConfig(snapshot, preset, "clean"));
		applyEffectiveConfig(ctx, pi, state, transient);
	};
	const restore = () => applyEffectiveConfig(ctx, pi, state, snapshot);
	await pickGallery(ctx, snapshot.preset, apply, restore);
}

export async function runPieConfigTool(params: PieToolParams, ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState) {
	const loaded = loadConfig(ctx.cwd, ctx.isProjectTrusted());
	if (params.action === "read") return toolResult("read", loaded);
	if (params.action === "list_presets") return toolResult("presets", presetDetails());
	if (params.action === "validate") {
		const target = params.config ?? loaded.effective;
		return toolResult("validate", validateConfig(target, { strict: params.strict }));
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
	if (params.action === "set_preset") return updateConfigTool(params, ctx, pi, state, (current) => {
		if (!params.preset) throw new Error("set_preset requires preset");
		return applyPresetConfig(current, params.preset, params.applyMode ?? "merge");
	});
	if (params.action === "set_footer_segments") return updateConfigTool(params, ctx, pi, state, (current) => {
		if (!params.footerSegments) throw new Error("set_footer_segments requires footerSegments");
		return { ...current, footer: { ...current.footer, enabled: true, segments: params.footerSegments } };
	});
	if (params.action === "toggle_compact") return updateConfigTool(params, ctx, pi, state, (current) => ({ ...current, compact: !Boolean(materializeConfig(current).compact) }));
	if (params.action === "set_theme") return updateConfigTool(params, ctx, pi, state, (current) => {
		if (!params.theme) throw new Error("set_theme requires theme");
		return { ...current, theme: params.theme };
	});
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

async function updateConfigTool(params: PieToolParams, ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState, update: (current: PieConfig) => PieConfig) {
	const loaded = loadConfig(ctx.cwd, ctx.isProjectTrusted());
	if (params.scope === "effective" && !params.dryRun) return toolResult(`${params.action} rejected`, { error: "effective scope is read-only; set dryRun true or choose global/project" }, true);
	const target = params.scope === "effective" ? undefined : resolveToolWriteTarget(ctx, params.scope);
	if (target && "error" in target) return toolResult(`${params.action} rejected`, target, true);
	const current = target ? (readConfigFile(target.path) ?? {}) : loaded.effective;
	const next = update(current);
	const validation = validateConfig(materializeConfig(next), { strict: params.strict });
	if (!validation.valid) return toolResult(`${params.action} rejected`, validation, true);
	if (!params.dryRun && target) {
		writeConfigFile(target.path, next);
		applyPie(ctx, pi, state);
	}
	return toolResult(params.action, { path: target?.path, scope: params.scope ?? target?.scope ?? "effective", writable: Boolean(target), dryRun: Boolean(params.dryRun || !target), config: next, validation });
}

// /pie import <path>: reads a JSON file, validates, confirms, writes to chosen scope.
// URL import is deferred — pi.exec runtime shape is unverified; for now suggest a local download.
async function importConfig(arg: string, ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState): Promise<void> {
	const source = arg.trim();
	if (!source) {
		ctx.ui.notify("Usage: /pie import <path-to-pie-ui.json>", "error");
		return;
	}
	if (source.startsWith("http://") || source.startsWith("https://")) {
		ctx.ui.notify("URL import not yet supported. Download the JSON locally then /pie import <path>.", "warning");
		return;
	}
	const errors: string[] = [];
	const candidate = readConfigFile(source, errors);
	if (!candidate) {
		ctx.ui.notify(`Import failed: ${errors[0] ?? `not found: ${source}`}`, "error");
		return;
	}
	const validation = validateConfig(materializeConfig(candidate));
	if (!validation.valid) {
		ctx.ui.notify(`Import invalid: ${validation.errors[0]}`, "error");
		return;
	}
	const target = await chooseWriteTarget(ctx);
	if (!target) return;
	const before = readConfigFile(target.path) ?? {};
	const summary = summarizeChange(materializeConfig(before), materializeConfig(candidate));
	const confirmed = await ctx.ui.confirm("Apply imported config?", `source: ${source}\ntarget: ${target.path}\nchange: ${summary}`);
	if (!confirmed) return;
	appendHistory({ ts: Date.now(), scope: target.scope, path: target.path, previous: before, next: candidate });
	writeConfigFile(target.path, candidate);
	applyPie(ctx, pi, state);
	ctx.ui.notify(`Fried Apple Pie imported from ${source}`, "info");
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
		Object.assign(next, applyPresetConfig(next, preset, "clean"));
	}
	if (action === "theme") {
		const names = ctx.ui.getAllThemes().map((theme) => theme.name).sort();
		const selected = await ctx.ui.select("Fried Apple Pie theme", names);
		if (!selected) return;
		next.theme = selected;
	}
	if (action === "mode") {
		const selected = await ctx.ui.select("Fried Apple Pie mode", [...MODE_NAMES]);
		if (!selected) return;
		next.mode = selected as PieMode;
	}
	if (action === "compact") next.compact = !Boolean(loaded.effective.compact);
	if (action === "footer") {
		// picker handles bare-string entries only; conditional `when` rules must be edited via /pie edit-json or pie_config patch.
		const current = loaded.effective.footer?.segments?.map((entry) => (typeof entry === "string" ? entry : entry.id));
		const segments = await pickFooterSegments(ctx, current);
		if (!segments) return;
		next.footer = { ...next.footer, enabled: true, segments };
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
	const target = await chooseWriteTarget(ctx);
	if (!target) return;
	const summary = summarizeChange(loaded.effective, materializeConfig(next));
	const confirmed = await ctx.ui.confirm("Apply Fried Apple Pie config?", `target: ${target.path}\nchange: ${summary}`);
	if (!confirmed) return;
	writeConfigFile(target.path, next);
	applyPie(ctx, pi, state);
	ctx.ui.notify(`Fried Apple Pie updated: ${action}`, "info");
}

async function chooseWriteTarget(ctx: ExtensionContext): Promise<{ path: string; scope: "global" | "project" } | undefined> {
	if (!ctx.hasUI) return resolveWriteTarget(ctx.cwd, ctx.isProjectTrusted());
	const globalTarget = resolveWriteTarget(ctx.cwd, ctx.isProjectTrusted(), "global");
	const options = [`global: ${globalTarget.path}`];
	if (ctx.isProjectTrusted()) {
		const projectTarget = resolveWriteTarget(ctx.cwd, true, "project");
		options.unshift(`project: ${projectTarget.path}`);
	}
	const selected = await ctx.ui.select("Write Fried Apple Pie config", options);
	if (!selected) return undefined;
	return selected.startsWith("project: ") ? resolveWriteTarget(ctx.cwd, true, "project") : globalTarget;
}

function summarizeChange(before: PieConfig, after: PieConfig): string {
	const changed: string[] = [];
	for (const key of ["preset", "theme", "mode", "compact", "header", "footer", "widget", "tools"] as const) {
		if (JSON.stringify(before[key]) !== JSON.stringify(after[key])) changed.push(key);
	}
	return changed.length ? changed.join(", ") : "no effective change";
}

// renders the most recent history entries as a panel. used by /pie history.
export function historyLines(entries: HistoryEntry[]): string[] {
	if (entries.length === 0) return ["history empty. preset switches are recorded once /pie preset runs."];
	const lines: string[] = [`${entries.length} entr${entries.length === 1 ? "y" : "ies"} (most recent last). /pie undo restores the latest.`];
	const tail = entries.slice(-10);
	for (let i = 0; i < tail.length; i++) {
		const entry = tail[i];
		const idx = entries.length - tail.length + i + 1;
		const when = new Date(entry.ts).toISOString().replace("T", " ").replace(/\..*$/, "");
		const from = entry.previous.preset ?? "custom";
		const to = entry.next.preset ?? "custom";
		lines.push(`#${idx} ${when} [${entry.scope}] ${from} -> ${to}`);
	}
	return lines;
}

// key-by-key diff between two configs. used by /pie diff.
export function diffLines(before: PieConfig, after: PieConfig): string[] {
	const keys = ["preset", "theme", "mode", "compact", "persona", "header", "footer", "widget", "tools", "thinking", "working"] as const;
	const lines: string[] = [];
	let changes = 0;
	for (const key of keys) {
		const a = JSON.stringify(before[key]);
		const b = JSON.stringify(after[key]);
		if (a === b) continue;
		changes++;
		lines.push(`${key}:`);
		lines.push(`  before: ${a ?? "undefined"}`);
		lines.push(`  after:  ${b ?? "undefined"}`);
		lines.push("");
	}
	if (changes === 0) lines.push("no effective change");
	else lines.push(`${changes} key${changes === 1 ? "" : "s"} changed`);
	return lines;
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
	const persona = resolvePersona(loaded.effective.persona, loaded.effective.preset);
	return [
		`preset: ${loaded.effective.preset ?? "custom"}`,
		`theme: ${loaded.effective.theme ?? "default"}`,
		`persona: ${loaded.effective.persona ?? "auto"} (${persona ? `${persona.spinner} · ${persona.verbs[0]}` : "none"})`,
		`model: ${ctx.model?.id ?? "no-model"}`,
		`cwd: ${ctx.cwd}`,
		`config: ${loaded.projectTrusted ? loaded.paths.projectPath : loaded.paths.globalPath}`,
		"",
		"/pie edit            configure preset, theme, footer, header, widget, tools",
		"/pie persona <name>  switch spinner+verb pack (default, terse, arc, startrek, medieval, pirate, mlengineer)",
		"/pie export          show effective config",
		"/pie doctor          validate config and conflicts",
		"/pie reset           return to minimal preset",
	];
}

function doctorLines(loaded: ReturnType<typeof loadConfig>, ctx: ExtensionContext, pi: ExtensionAPI, strict = false): string[] {
	const lines: string[] = [];
	lines.push(`global: ${loaded.paths.globalPath}`);
	lines.push(`project: ${loaded.paths.projectPath}`);
	lines.push(`project trusted: ${loaded.projectTrusted ? "yes" : "no"}`);
	lines.push(`active preset: ${loaded.effective.preset ?? "custom"}`);
	lines.push(`active theme: ${loaded.effective.theme ?? "default"}`);
	if (loaded.effective.layers?.length) lines.push(`active layers: ${loaded.effective.layers.join(", ")}`);
	for (const error of loaded.readErrors) lines.push(`read error: ${error}`);
	const validation = strict ? validateConfig(loaded.effective, { strict: true }) : loaded.validation;
	for (const error of validation.errors) lines.push(`config error: ${error}`);
	for (const warning of validation.warnings) lines.push(`config warning: ${warning}`);
	const themes = new Set(ctx.ui.getAllThemes().map((theme) => theme.name));
	if (loaded.effective.theme && !themes.has(loaded.effective.theme)) lines.push(`theme unavailable: ${loaded.effective.theme}`);
	const commands = pi.getCommands().map((command) => command.name);
	const conflicts = commands.filter((name) => ["footer", "powerline-footer", "tool-display"].includes(name));
	for (const conflict of conflicts) lines.push(`possible UI conflict: /${conflict}`);
	if (conflicts.length > 0 && loaded.effective.mode === "full") lines.push("recommendation: set /pie mode status-only (minimal surface), theme-only, or footer-only if another UI package owns a surface");
	const hasConfigOrConflictIssue = lines.length > 5;
	const deps = captureDependencyLines();
	lines.push(...deps);
	if (!hasConfigOrConflictIssue && !deps.some((line) => line.startsWith("capture unavailable:"))) lines.push("ok");
	return lines;
}

export function captureDependencyLines(probe: (name: string) => string | undefined = commandPath): string[] {
	const tools = ["vhs", "ttyd", "ffmpeg"] as const;
	const results = tools.map((name) => ({ name, path: probe(name) }));
	const missing = results.filter((result) => !result.path).map((result) => result.name);
	const lines = results.map((result) => `capture dependency: ${result.name} ${result.path ? `ok (${result.path})` : "missing"}`);
	if (missing.length > 0) lines.push(`capture unavailable: install ${missing.join(", ")} on PATH`);
	return lines;
}

function commandPath(name: string): string | undefined {
	const result = spawnSync("which", [name], { encoding: "utf8" });
	if (result.status !== 0) return undefined;
	const path = result.stdout.trim().split("\n")[0];
	return path || undefined;
}
