import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth, type Component } from "@earendil-works/pi-tui";
import type { FooterSegment, PieConfig, PresetName } from "./config.ts";
import { FOOTER_SEGMENTS, PRESET_NAMES } from "./config.ts";

type ThemeLike = {
	fg(name: string, text: string): string;
	bg(name: string, text: string): string;
	bold(text: string): string;
};

type FooterData = {
	getGitBranch(): string | null;
	getExtensionStatuses(): ReadonlyMap<string, string>;
	onBranchChange(callback: () => void): () => void;
};

export type RenderState = {
	working: boolean;
	requestRender?: () => void;
};

export type EditAction = "preset" | "theme" | "mode" | "compact" | "footer" | "header" | "widget" | "tools" | "cancel";

export function createFooter(config: PieConfig, ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState, theme: ThemeLike, footerData: FooterData): Component & { dispose(): void } {
	let disposed = false;
	const unsubscribe = footerData.onBranchChange(() => state.requestRender?.());
	return {
		dispose() {
			disposed = true;
			unsubscribe();
		},
		invalidate() {},
		render(width: number): string[] {
			if (disposed || config.footer?.enabled === false) return [];
			const segments = config.footer?.segments ?? [];
			const sep = theme.fg("muted", config.footer?.separator ?? " · ");
			const rendered = segments
				.map((segment) => renderSegment(segment, config, ctx, pi, state, theme, footerData))
				.filter((segment): segment is string => Boolean(segment));
			const line = rendered.join(sep);
			const prefix = visibleWidth(line) < width ? " " : "";
			return [truncateToWidth(prefix + line, width)];
		},
	};
}

export function createHeader(config: PieConfig, theme: ThemeLike): Component {
	return {
		invalidate() {},
		render(width: number): string[] {
			if (config.header?.enabled === false) return [];
			const title = config.header?.title ?? "Fried Apple Pie";
			const subtitle = config.header?.subtitle ?? config.preset ?? "";
			const line = theme.fg("accent", ` ${title} `) + theme.fg("muted", subtitle ? ` ${subtitle}` : "");
			return [truncateToWidth(line, width)];
		},
	};
}

export function widgetLines(config: PieConfig): string[] | undefined {
	if (!config.widget?.enabled) return undefined;
	const lines = config.widget.lines ?? [];
	if (lines.length === 0) return undefined;
	return lines;
}

export async function pickPreset(ctx: ExtensionContext, active: string | undefined): Promise<PresetName | undefined> {
	if (ctx.mode !== "tui") return undefined;
	return ctx.ui.custom<PresetName | undefined>(
		(_tui, theme, _keybindings, done) => new PresetPicker(theme as ThemeLike, active, done),
		{
			overlay: true,
			overlayOptions: {
				anchor: "center",
				width: "58%",
				minWidth: 42,
				maxHeight: "70%",
				margin: 1,
			},
		},
	);
}

export async function pickEditAction(ctx: ExtensionContext, config: PieConfig): Promise<EditAction | undefined> {
	if (ctx.mode !== "tui") return undefined;
	return ctx.ui.custom<EditAction | undefined>(
		(_tui, theme, _keybindings, done) => new EditPicker(theme as ThemeLike, config, done),
		{
			overlay: true,
			overlayOptions: {
				anchor: "center",
				width: "68%",
				minWidth: 54,
				maxHeight: "75%",
				margin: 1,
			},
		},
	);
}

export async function pickFooterSegments(ctx: ExtensionContext, active: FooterSegment[] | undefined): Promise<FooterSegment[] | undefined> {
	if (ctx.mode !== "tui") return undefined;
	return ctx.ui.custom<FooterSegment[] | undefined>(
		(_tui, theme, _keybindings, done) => new FooterSegmentPicker(theme as ThemeLike, active, done),
		{
			overlay: true,
			overlayOptions: {
				anchor: "center",
				width: "64%",
				minWidth: 54,
				maxHeight: "80%",
				margin: 1,
			},
		},
	);
}

export async function showPanel(ctx: ExtensionContext, title: string, lines: string[]): Promise<void> {
	if (ctx.mode !== "tui") {
		ctx.ui.notify(lines.slice(0, 3).join(" · ") || title, "info");
		return;
	}
	await ctx.ui.custom<void>(
		(_tui, theme, _keybindings, done) => new TextPanel(theme as ThemeLike, title, lines, done),
		{
			overlay: true,
			overlayOptions: {
				anchor: "center",
				width: "90%",
				maxHeight: "85%",
				margin: 1,
			},
		},
	);
}

class PresetPicker implements Component {
	private index: number;
	constructor(
		private theme: ThemeLike,
		private active: string | undefined,
		private done: (result: PresetName | undefined) => void,
	) {
		const activeIndex = PRESET_NAMES.findIndex((name) => name === active);
		this.index = activeIndex >= 0 ? activeIndex : 0;
	}

	render(width: number): string[] {
		const w = Math.max(42, width);
		const lines = [
			pad(this.theme.bg("toolPendingBg", this.theme.bold(" Fried Apple Pie presets ") + this.theme.fg("muted", "j/k enter q")), w),
		];
		for (let i = 0; i < PRESET_NAMES.length; i++) {
			const name = PRESET_NAMES[i];
			const selected = i === this.index;
			const active = name === this.active ? " active" : "";
			const row = `${selected ? ">" : " "} ${name}${active}`;
			lines.push(selected ? this.theme.bg("selectedBg", pad(this.theme.fg("accent", row), w)) : pad(row, w));
		}
		return lines;
	}

	handleInput(data: string): void {
		if (data === "q" || data === "\u001b") {
			this.done(undefined);
			return;
		}
		if (data === "j") this.index = Math.min(PRESET_NAMES.length - 1, this.index + 1);
		if (data === "k") this.index = Math.max(0, this.index - 1);
		if (data === "\r" || data === "\n") this.done(PRESET_NAMES[this.index]);
	}

	invalidate(): void {}
}

class EditPicker implements Component {
	private index = 0;
	private readonly actions: Array<{ id: EditAction; label: string }> = [
		{ id: "preset", label: "preset" },
		{ id: "theme", label: "theme" },
		{ id: "mode", label: "compatibility mode" },
		{ id: "compact", label: "compact mode" },
		{ id: "footer", label: "footer segments" },
		{ id: "header", label: "header toggle" },
		{ id: "widget", label: "widget toggle/text" },
		{ id: "tools", label: "tool expansion" },
		{ id: "cancel", label: "cancel" },
	];

	constructor(
		private theme: ThemeLike,
		private config: PieConfig,
		private done: (result: EditAction | undefined) => void,
	) {}

	render(width: number): string[] {
		const w = Math.max(54, width);
		const lines = [
			pad(this.theme.bg("toolPendingBg", this.theme.bold(" Fried Apple Pie editor ") + this.theme.fg("muted", "j/k enter q")), w),
			pad(this.theme.fg("muted", ` preset ${this.config.preset ?? "custom"} · theme ${this.config.theme ?? "default"}`), w),
		];
		for (let i = 0; i < this.actions.length; i++) {
			const action = this.actions[i];
			const selected = i === this.index;
			const row = `${selected ? ">" : " "} ${action.label}${this.suffix(action.id)}`;
			lines.push(selected ? this.theme.bg("selectedBg", pad(this.theme.fg("accent", row), w)) : pad(row, w));
		}
		return lines;
	}

	handleInput(data: string): void {
		if (data === "q" || data === "\u001b") {
			this.done(undefined);
			return;
		}
		if (data === "j") this.index = Math.min(this.actions.length - 1, this.index + 1);
		if (data === "k") this.index = Math.max(0, this.index - 1);
		if (data === "\r" || data === "\n") this.done(this.actions[this.index].id);
	}

	invalidate(): void {}

	private suffix(action: EditAction): string {
		if (action === "compact") return `: ${this.config.compact ? "on" : "off"}`;
		if (action === "mode") return `: ${this.config.mode ?? "full"}`;
		if (action === "header") return `: ${this.config.header?.enabled === false ? "off" : "on"}`;
		if (action === "widget") return `: ${this.config.widget?.enabled ? "on" : "off"}`;
		if (action === "tools") return `: ${this.config.tools?.expanded ? "expanded" : "compact"}`;
		if (action === "footer") return `: ${(this.config.footer?.segments ?? []).join(",")}`;
		return "";
	}
}

class FooterSegmentPicker implements Component {
	private index = 0;
	private selected: Set<FooterSegment>;

	constructor(
		private theme: ThemeLike,
		active: FooterSegment[] | undefined,
		private done: (result: FooterSegment[] | undefined) => void,
	) {
		this.selected = new Set(active?.length ? active : ["model", "cwd", "branch", "status", "context"]);
	}

	render(width: number): string[] {
		const w = Math.max(54, width);
		const lines = [
			pad(this.theme.bg("toolPendingBg", this.theme.bold(" Footer segments ") + this.theme.fg("muted", "j/k space enter c/f/a q")), w),
			pad(this.theme.fg("muted", "space toggles · c compact order · f full order · a all"), w),
		];
		for (let i = 0; i < FOOTER_SEGMENTS.length; i++) {
			const segment = FOOTER_SEGMENTS[i];
			const selected = i === this.index;
			const checked = this.selected.has(segment) ? "[x]" : "[ ]";
			const row = `${selected ? ">" : " "} ${checked} ${segment}`;
			lines.push(selected ? this.theme.bg("selectedBg", pad(this.theme.fg("accent", row), w)) : pad(row, w));
		}
		return lines;
	}

	handleInput(data: string): void {
		if (data === "q" || data === "\u001b") {
			this.done(undefined);
			return;
		}
		if (data === "j") this.index = Math.min(FOOTER_SEGMENTS.length - 1, this.index + 1);
		if (data === "k") this.index = Math.max(0, this.index - 1);
		if (data === " ") {
			const segment = FOOTER_SEGMENTS[this.index];
			if (this.selected.has(segment)) this.selected.delete(segment);
			else this.selected.add(segment);
		}
		if (data === "c") this.selected = new Set(["model", "cwd", "branch", "status", "context"]);
		if (data === "f") this.selected = new Set(["model", "thinking", "cwd", "branch", "status", "context", "tokens"]);
		if (data === "a") this.selected = new Set(FOOTER_SEGMENTS);
		if (data === "\r" || data === "\n") this.done(FOOTER_SEGMENTS.filter((segment) => this.selected.has(segment)));
	}

	invalidate(): void {}
}

class TextPanel implements Component {
	private scroll = 0;
	constructor(
		private theme: ThemeLike,
		private title: string,
		private lines: string[],
		private done: () => void,
	) {}

	render(width: number): string[] {
		const w = Math.max(48, width);
		const height = Math.max(6, Math.min(28, (process.stdout.rows || 34) - 8));
		const maxScroll = Math.max(0, this.lines.length - height);
		this.scroll = Math.max(0, Math.min(this.scroll, maxScroll));
		const out = [pad(this.theme.bg("toolPendingBg", this.theme.bold(` ${this.title} `) + this.theme.fg("muted", "j/k q")), w)];
		for (const line of this.lines.slice(this.scroll, this.scroll + height)) out.push(truncateToWidth(line, w));
		out.push(this.theme.fg("muted", pad(` ${this.scroll + 1}-${Math.min(this.scroll + height, this.lines.length)} of ${this.lines.length}`, w)));
		return out;
	}

	handleInput(data: string): void {
		if (data === "q" || data === "\u001b") this.done();
		if (data === "j") this.scroll++;
		if (data === "k") this.scroll--;
	}

	invalidate(): void {
		this.scroll = Math.max(0, this.scroll);
	}
}

function renderSegment(segment: FooterSegment, config: PieConfig, ctx: ExtensionContext, pi: ExtensionAPI, state: RenderState, theme: ThemeLike, footerData: FooterData): string | undefined {
	if (segment === "model") return theme.fg("accent", ctx.model?.id ?? "no-model");
	if (segment === "thinking") return theme.fg("thinkingText", config.compact ? String(pi.getThinkingLevel()) : `think:${pi.getThinkingLevel()}`);
	if (segment === "cwd") return theme.fg("success", compactPath(ctx.cwd));
	if (segment === "branch") {
		const branch = footerData.getGitBranch();
		return branch ? theme.fg("borderAccent", branch) : undefined;
	}
	if (segment === "status") return theme.fg(state.working ? "warning" : "muted", config.compact ? (state.working ? "wrk" : "rdy") : state.working ? "Working" : "Ready");
	if (segment === "context") return theme.fg("mdCode", contextLeft(ctx, Boolean(config.compact)));
	if (segment === "tokens") return theme.fg("dim", tokenText(ctx));
	if (segment === "cost") return theme.fg("dim", costText(ctx));
	if (segment === "preset") return theme.fg("muted", config.preset ?? "custom");
}

function contextLeft(ctx: ExtensionContext, compact: boolean): string {
	const usage = ctx.getContextUsage();
	if (!usage || usage.percent === null) return compact ? "ctx --" : "Context -- left";
	const left = Math.max(0, Math.min(100, Math.round(100 - usage.percent)));
	return compact ? `ctx ${left}%` : `Context ${left}% left`;
}

function tokenText(ctx: ExtensionContext): string {
	const usage = usageTotals(ctx);
	return `tok ${formatNumber(usage.input)}/${formatNumber(usage.output)}`;
}

function costText(ctx: ExtensionContext): string {
	return `$${usageTotals(ctx).cost.toFixed(3)}`;
}

function usageTotals(ctx: ExtensionContext): { input: number; output: number; cost: number } {
	let input = 0;
	let output = 0;
	let cost = 0;
	const entries = (ctx.sessionManager as unknown as { getBranch?: () => unknown[] }).getBranch?.() ?? [];
	for (const entry of entries) {
		const message = (entry as { type?: string; message?: { role?: string; usage?: { input?: number; output?: number; cost?: { total?: number } } } }).message;
		if (!message || message.role !== "assistant" || !message.usage) continue;
		input += message.usage.input ?? 0;
		output += message.usage.output ?? 0;
		cost += message.usage.cost?.total ?? 0;
	}
	return { input, output, cost };
}

function compactPath(cwd: string): string {
	const home = process.env.HOME;
	const path = home && cwd.startsWith(home) ? `~${cwd.slice(home.length)}` : cwd;
	const parts = path.split("/");
	if (parts.length <= 4) return path;
	return `${parts[0] || "/"}…/${parts.slice(-2).join("/")}`;
}

function formatNumber(value: number): string {
	if (value < 1000) return String(value);
	return `${(value / 1000).toFixed(1)}k`;
}

function pad(text: string, width: number): string {
	const visible = visibleWidth(text);
	return visible < width ? text + " ".repeat(width - visible) : truncateToWidth(text, width);
}
