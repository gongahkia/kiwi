import type { AgentToolResult, ExtensionAPI, ToolDefinition, ToolRenderResultOptions } from "@earendil-works/pi-coding-agent";
import { createBashToolDefinition, createEditToolDefinition, createGrepToolDefinition, createReadToolDefinition } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, type Component } from "@earendil-works/pi-tui";
import type { ToolRenderStyle } from "./config.ts";

type ThemeLike = {
	fg(name: string, text: string): string;
	bg(name: string, text: string): string;
	bold(text: string): string;
};

export const RENDERED_TOOL_NAMES = ["bash", "edit", "read", "grep"] as const;
export type RenderedToolName = (typeof RENDERED_TOOL_NAMES)[number];

export function registerPresetToolRenderers(pi: ExtensionAPI, cwd: string, getStyle: () => ToolRenderStyle | undefined): void {
	const builtIns = {
		bash: createBashToolDefinition(cwd),
		edit: createEditToolDefinition(cwd),
		read: createReadToolDefinition(cwd),
		grep: createGrepToolDefinition(cwd),
	};
	for (const name of RENDERED_TOOL_NAMES) {
		const base = builtIns[name] as ToolDefinition<any, any, any>;
		pi.registerTool({
			...base,
			renderCall: (args, theme, context) => renderToolCall(getStyle() ?? "minimal", name, args, theme, context),
			renderResult: (result, options, theme, context) => renderToolResult(getStyle() ?? "minimal", name, result, options, theme, context),
		});
	}
}

export function renderToolCall(style: ToolRenderStyle, name: RenderedToolName, args: unknown, theme: ThemeLike, context?: { executionStarted?: boolean }): Component {
	const target = summarizeArgs(name, args);
	const state = context?.executionStarted ? "running" : "queued";
	return lineComponent((width) => styleLines(style, "call", name, target, state, theme, width));
}

export function renderToolResult(
	style: ToolRenderStyle,
	name: RenderedToolName,
	result: AgentToolResult<unknown>,
	options: ToolRenderResultOptions,
	theme: ThemeLike,
	context?: { isError?: boolean },
): Component {
	const status = context?.isError ? "error" : options.isPartial ? "partial" : "ok";
	const output = summarizeResult(name, result);
	return lineComponent((width) => styleLines(style, "result", name, output, status, theme, width, options.expanded));
}

function styleLines(style: ToolRenderStyle, phase: "call" | "result", name: RenderedToolName, text: string, meta: string, theme: ThemeLike, width: number, expanded = false): string[] {
	const label = theme.bold(name);
	const muted = (value: string) => theme.fg("muted", value);
	const accent = (value: string) => theme.fg(phase === "result" && meta === "error" ? "error" : "accent", value);
	const body = text || "(empty)";
	if (style === "dense") return [truncateToWidth(`${accent(phase === "call" ? ">" : "<")} ${label} ${muted(meta)} ${body}`, width)];
	if (style === "pill") return [truncateToWidth(`${theme.bg("toolPendingBg", ` ${label} `)} ${muted(meta)} ${body}`, width)];
	if (style === "minimal") return [truncateToWidth(`${name}: ${body}`, width)];
	const first = truncateToWidth(`+ ${label} ${muted(meta)}`, width);
	const lines = [first, truncateToWidth(`| ${body}`, width)];
	if (expanded) lines.push(...expandedLines(resultBody(text), width, theme));
	lines.push(truncateToWidth("+", width));
	return lines;
}

function summarizeArgs(name: RenderedToolName, args: unknown): string {
	const obj = isObject(args) ? args : {};
	if (name === "bash") return stringValue(obj.command) || stringifyShort(args);
	if (name === "read") return stringValue(obj.path) || stringifyShort(args);
	if (name === "grep") return [stringValue(obj.pattern), stringValue(obj.path) || stringValue(obj.glob)].filter(Boolean).join(" in ") || stringifyShort(args);
	if (name === "edit") {
		const count = Array.isArray(obj.edits) ? obj.edits.length : 0;
		const suffix = count === 1 ? "1 edit" : `${count} edits`;
		return [stringValue(obj.path), suffix].filter(Boolean).join(" ");
	}
	return stringifyShort(args);
}

function summarizeResult(name: RenderedToolName, result: AgentToolResult<unknown>): string {
	const details = isObject(result.details) ? result.details : {};
	if (name === "edit" && typeof details.diff === "string" && details.diff.trim()) return compact(details.diff);
	const text = resultBody(textOutput(result));
	return text || "(no output)";
}

function textOutput(result: AgentToolResult<unknown>): string {
	return (result.content ?? [])
		.map((item) => {
			const content = item as { type: string; text?: string; mimeType?: string };
			if (content.type === "text") return content.text ?? "";
			if (content.type === "image") return `[image ${content.mimeType ?? "unknown"}]`;
			return `[${content.type}]`;
		})
		.filter(Boolean)
		.join("\n");
}

function expandedLines(text: string, width: number, theme: ThemeLike): string[] {
	return text
		.split("\n")
		.slice(0, 6)
		.filter(Boolean)
		.map((line) => truncateToWidth(theme.fg("toolOutput", `| ${line}`), width));
}

function resultBody(text: string): string {
	return compact(text).slice(0, 240);
}

function compact(text: string): string {
	return text.replace(/\s+/g, " ").trim();
}

function stringifyShort(value: unknown): string {
	try {
		return compact(JSON.stringify(value));
	} catch {
		return String(value);
	}
}

function stringValue(value: unknown): string | undefined {
	return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function isObject(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function lineComponent(render: (width: number) => string[]): Component {
	return {
		invalidate() {},
		render,
	};
}
