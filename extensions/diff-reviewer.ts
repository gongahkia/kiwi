import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

type Side = "context" | "removed" | "added" | "empty";
type ViewMode = "overview" | "detail";

type DiffRow = {
	leftNo: string;
	leftText: string;
	leftKind: Side;
	rightNo: string;
	rightText: string;
	rightKind: Side;
};

type FileReview = {
	path: string;
	rows: DiffRow[];
	additions: number;
	removals: number;
};

type PendingFile = {
	path: string;
	absPath: string;
	oldContent: string;
};

const reviews: FileReview[] = [];
const pendingFiles = new Map<string, PendingFile>();
const toolCallPaths = new Map<string, string>();
const successfulPaths = new Set<string>();
let activeIndex = 0;
let scroll = 0;
let viewMode: ViewMode = "overview";
let activeComponent: DiffReviewComponent | undefined;
let requestOverlayRender: (() => void) | undefined;
let overlayOpen = false;

function rawPath(input: unknown): string | undefined {
	if (!input || typeof input !== "object") return undefined;
	const value = (input as { path?: unknown; file_path?: unknown }).path ?? (input as { file_path?: unknown }).file_path;
	return typeof value === "string" ? value : undefined;
}

function resolvePath(path: string, cwd: string): string {
	return path.startsWith("/") ? path : resolve(cwd, path);
}

function displayPath(path: string, cwd: string): string {
	const abs = resolvePath(path, cwd);
	return abs.startsWith(`${cwd}/`) ? abs.slice(cwd.length + 1) : path;
}

function readText(path: string): string {
	return existsSync(path) ? readFileSync(path, "utf8") : "";
}

function parseDisplayDiff(diffText: string): DiffRow[] {
	const parsed = diffText.split("\n").map((line) => {
		const match = line.match(/^([+\- ])(\s*\d*)\s(.*)$/);
		if (!match) return { prefix: " " as const, no: "", text: line };
		return { prefix: match[1] as "+" | "-" | " ", no: match[2], text: match[3] };
	});

	const rows: DiffRow[] = [];
	let i = 0;
	while (i < parsed.length) {
		const line = parsed[i];
		if (line.prefix === "-") {
			const removed = [] as typeof parsed;
			while (i < parsed.length && parsed[i].prefix === "-") removed.push(parsed[i++]);
			const added = [] as typeof parsed;
			while (i < parsed.length && parsed[i].prefix === "+") added.push(parsed[i++]);
			const count = Math.max(removed.length, added.length);
			for (let j = 0; j < count; j++) {
				const left = removed[j];
				const right = added[j];
				rows.push({
					leftNo: left?.no ?? "",
					leftText: left?.text ?? "",
					leftKind: left ? "removed" : "empty",
					rightNo: right?.no ?? "",
					rightText: right?.text ?? "",
					rightKind: right ? "added" : "empty",
				});
			}
			continue;
		}
		if (line.prefix === "+") {
			rows.push({ leftNo: "", leftText: "", leftKind: "empty", rightNo: line.no, rightText: line.text, rightKind: "added" });
			i++;
			continue;
		}
		rows.push({
			leftNo: line.no,
			leftText: line.text,
			leftKind: "context",
			rightNo: line.no,
			rightText: line.text,
			rightKind: "context",
		});
		i++;
	}
	return rows;
}

function contentLines(content: string): string[] {
	const lines = content.split("\n");
	if (lines[lines.length - 1] === "") lines.pop();
	return lines;
}

function displayDiffFromContents(oldContent: string, newContent: string): string {
	const oldLines = contentLines(oldContent);
	const newLines = contentLines(newContent);
	const width = String(Math.max(oldLines.length, newLines.length, 1)).length;
	const dp = Array.from({ length: oldLines.length + 1 }, () => Array(newLines.length + 1).fill(0));
	for (let i = oldLines.length - 1; i >= 0; i--) {
		for (let j = newLines.length - 1; j >= 0; j--) {
			dp[i][j] = oldLines[i] === newLines[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
		}
	}
	let i = 0;
	let j = 0;
	let oldNo = 1;
	let newNo = 1;
	const out: string[] = [];
	while (i < oldLines.length || j < newLines.length) {
		if (i < oldLines.length && j < newLines.length && oldLines[i] === newLines[j]) {
			out.push(` ${String(oldNo).padStart(width, " ")} ${oldLines[i]}`);
			i++;
			j++;
			oldNo++;
			newNo++;
		} else if (j < newLines.length && (i === oldLines.length || dp[i][j + 1] >= dp[i + 1][j])) {
			out.push(`+${String(newNo++).padStart(width, " ")} ${newLines[j++]}`);
		} else if (i < oldLines.length) {
			out.push(`-${String(oldNo++).padStart(width, " ")} ${oldLines[i++]}`);
		}
	}
	return out.join("\n");
}

function colorCell(text: string, kind: Side, theme: any): string {
	if (kind === "removed") return theme.bg("toolErrorBg", theme.fg("toolDiffRemoved", text));
	if (kind === "added") return theme.bg("toolSuccessBg", theme.fg("toolDiffAdded", text));
	if (kind === "empty") return theme.fg("muted", text);
	return theme.fg("toolDiffContext", text);
}

function padVisible(text: string, width: number): string {
	const visible = visibleWidth(text);
	return visible < width ? text + " ".repeat(width - visible) : text;
}

function cell(lineNo: string, text: string, kind: Side, width: number, theme: any): string {
	const no = (lineNo.trim() || " ").padStart(4, " ");
	const prefix = `${no} │ `;
	const bodyWidth = Math.max(1, width - visibleWidth(prefix));
	const content = truncateToWidth(text.replace(/\t/g, "   "), bodyWidth, "…");
	return colorCell(padVisible(prefix + content, width), kind, theme);
}

function reviewFromContents(file: PendingFile, newContent: string): FileReview | undefined {
	if (file.oldContent === newContent) return undefined;
	const rows = parseDisplayDiff(displayDiffFromContents(file.oldContent, newContent));
	return {
		path: file.path,
		rows,
		additions: rows.filter((row) => row.rightKind === "added").length,
		removals: rows.filter((row) => row.leftKind === "removed").length,
	};
}

function resetPending(): void {
	pendingFiles.clear();
	toolCallPaths.clear();
	successfulPaths.clear();
}

function snapshotToolCall(event: { toolCallId: string; input: unknown }, ctx: ExtensionContext): void {
	const path = rawPath(event.input);
	if (!path) return;
	const absPath = resolvePath(path, ctx.cwd);
	toolCallPaths.set(event.toolCallId, absPath);
	if (!pendingFiles.has(absPath)) {
		pendingFiles.set(absPath, {
			path: displayPath(path, ctx.cwd),
			absPath,
			oldContent: readText(absPath),
		});
	}
}

function markSuccessfulMutation(event: { toolCallId: string; input: unknown }, ctx: ExtensionContext): void {
	const path = rawPath(event.input);
	const absPath = toolCallPaths.get(event.toolCallId) ?? (path ? resolvePath(path, ctx.cwd) : undefined);
	if (!absPath) return;
	successfulPaths.add(absPath);
	toolCallPaths.delete(event.toolCallId);
}

function finalizePendingReviews(ctx: ExtensionContext): boolean {
	const nextReviews: FileReview[] = [];
	for (const [absPath, file] of pendingFiles) {
		if (!successfulPaths.has(absPath)) continue;
		const review = reviewFromContents(file, readText(file.absPath));
		if (review) nextReviews.push(review);
	}
	resetPending();
	if (nextReviews.length === 0) return false;
	reviews.splice(0, reviews.length, ...nextReviews);
	activeIndex = 0;
	scroll = 0;
	viewMode = "overview";
	activeComponent?.invalidate();
	requestOverlayRender?.();
	return true;
}

class DiffReviewComponent {
	private theme: any;
	private done: () => void;

	constructor(theme: any, done: () => void) {
		this.theme = theme;
		this.done = done;
	}

	render(width: number): string[] {
		return viewMode === "detail" ? this.renderDetail(width) : this.renderOverview(width);
	}

	private renderOverview(width: number): string[] {
		if (reviews.length === 0) return [];
		const w = Math.max(50, width);
		const listHeight = Math.max(4, Math.min(20, (process.stdout.rows || 36) - 8));
		activeIndex = Math.max(0, Math.min(activeIndex, reviews.length - 1));
		if (activeIndex < scroll) scroll = activeIndex;
		if (activeIndex >= scroll + listHeight) scroll = activeIndex - listHeight + 1;
		const maxScroll = Math.max(0, reviews.length - listHeight);
		scroll = Math.max(0, Math.min(scroll, maxScroll));

		const header = this.theme.bg(
			"toolPendingBg",
			padVisible(
				this.theme.bold(" Diff review overview ") +
					this.theme.fg("accent", `${reviews.length} file${reviews.length === 1 ? "" : "s"} changed`) +
					this.theme.fg("muted", "   j/k nav  enter/o/1 open  q close "),
				w,
			),
		);
		const lines = [header];
		const visible = reviews.slice(scroll, scroll + listHeight);
		for (let offset = 0; offset < visible.length; offset++) {
			const index = scroll + offset;
			const review = visible[offset];
			const selected = index === activeIndex;
			const prefix = `${selected ? "›" : " "} ${String(index + 1).padStart(2, " ")}. `;
			const stats = ` +${review.additions} -${review.removals} · ${review.rows.length} displayed`;
			const pathWidth = Math.max(8, w - visibleWidth(prefix) - visibleWidth(stats));
			let line = prefix + this.theme.fg(selected ? "accent" : "text", truncateToWidth(review.path, pathWidth, "…")) + this.theme.fg("muted", stats);
			line = padVisible(line, w);
			lines.push(selected ? this.theme.bg("selectedBg", line) : line);
		}
		const footer = this.theme.fg("muted", ` ${scroll + 1}-${Math.min(scroll + listHeight, reviews.length)} of ${reviews.length}`);
		lines.push(padVisible(footer, w));
		return lines;
	}

	private renderDetail(width: number): string[] {
		const review = reviews[activeIndex];
		if (!review) return [];
		const w = Math.max(40, width);
		const paneWidth = Math.max(18, Math.floor((w - 3) / 2));
		const height = Math.max(8, Math.min(30, (process.stdout.rows || 36) - 8));
		const maxScroll = Math.max(0, review.rows.length - height);
		scroll = Math.max(0, Math.min(scroll, maxScroll));
		const header = this.theme.bg(
			"toolPendingBg",
			padVisible(
				this.theme.bold(` Diff review ${activeIndex + 1}/${reviews.length} `) +
					this.theme.fg("accent", review.path) +
					this.theme.fg("muted", "   j/k scroll  b overview  q close "),
				w,
			),
		);
		const before = this.theme.bold(padVisible(" Before", paneWidth));
		const after = this.theme.bold(padVisible(" After", paneWidth));
		const lines = [header, `${before} │ ${after}`];
		for (const row of review.rows.slice(scroll, scroll + height)) {
			lines.push(`${cell(row.leftNo, row.leftText, row.leftKind, paneWidth, this.theme)} │ ${cell(row.rightNo, row.rightText, row.rightKind, paneWidth, this.theme)}`);
		}
		const footer = this.theme.fg("muted", ` ${scroll + 1}-${Math.min(scroll + height, review.rows.length)} of ${review.rows.length}`);
		lines.push(padVisible(footer, w));
		return lines;
	}

	handleInput(data: string): void {
		if (data === "q") {
			this.done();
			return;
		}
		if (viewMode === "overview") this.handleOverviewInput(data);
		else this.handleDetailInput(data);
		this.invalidate();
		requestOverlayRender?.();
	}

	private handleOverviewInput(data: string): void {
		if (data === "\u001b") {
			this.done();
			return;
		}
		if (data === "j") {
			activeIndex = Math.min(reviews.length - 1, activeIndex + 1);
		} else if (data === "k") {
			activeIndex = Math.max(0, activeIndex - 1);
		} else if (data === "J") {
			activeIndex = Math.min(reviews.length - 1, activeIndex + 10);
		} else if (data === "K") {
			activeIndex = Math.max(0, activeIndex - 10);
		} else if (data === "\r" || data === "\n" || data === "o" || data === " ") {
			viewMode = "detail";
			scroll = 0;
		} else if (/^[1-9]$/.test(data)) {
			const index = Number(data) - 1;
			if (index < reviews.length) {
				activeIndex = index;
				viewMode = "detail";
				scroll = 0;
			}
		}
	}

	private handleDetailInput(data: string): void {
		if (data === "\u001b" || data === "b" || data === "\u007f") {
			viewMode = "overview";
			scroll = 0;
		} else if (data === "j") {
			scroll++;
		} else if (data === "k") {
			scroll--;
		} else if (data === "J") {
			scroll += 10;
		} else if (data === "K") {
			scroll -= 10;
		}
	}

	invalidate(): void {
		scroll = Math.max(0, scroll);
		activeComponent = this;
	}

	dispose(): void {
		activeComponent = undefined;
		requestOverlayRender = undefined;
		overlayOpen = false;
	}
}

function openOverlay(ctx: ExtensionContext): void {
	if (ctx.mode !== "tui" || overlayOpen || reviews.length === 0) return;
	overlayOpen = true;
	viewMode = "overview";
	scroll = 0;
	void ctx.ui.custom<void>((tui, theme, _keybindings, done) => {
		requestOverlayRender = () => tui.requestRender();
		const component = new DiffReviewComponent(theme, done);
		activeComponent = component;
		return component;
	}, {
		overlay: true,
		overlayOptions: {
			anchor: "center",
			width: "96%",
			maxHeight: "90%",
			margin: 1,
		},
	}).finally(() => {
		overlayOpen = false;
		activeComponent = undefined;
		requestOverlayRender = undefined;
	});
}

export default function (pi: ExtensionAPI) {
	pi.on("agent_start", () => {
		resetPending();
	});

	pi.on("tool_call", (event, ctx) => {
		if (event.toolName !== "edit" && event.toolName !== "write") return;
		snapshotToolCall(event, ctx);
	});

	pi.on("tool_result", (event, ctx) => {
		if (event.toolName !== "edit" && event.toolName !== "write") return;
		if (!event.isError) markSuccessfulMutation(event, ctx);
		else toolCallPaths.delete(event.toolCallId);
	});

	pi.on("agent_end", (_event, ctx) => {
		if (!finalizePendingReviews(ctx)) return;
		setTimeout(() => openOverlay(ctx), 0);
	});

	pi.registerCommand("diff-review", {
		description: "Show the in-terminal side-by-side review overlay for recent edit/write diffs",
		handler: async (_args, ctx) => {
			if (reviews.length === 0) ctx.ui.notify("No edit/write diffs captured yet", "info");
			else openOverlay(ctx);
		},
	});
}
