#!/usr/bin/env node
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const TOKENS = [
	"accent",
	"border",
	"borderAccent",
	"borderMuted",
	"success",
	"error",
	"warning",
	"muted",
	"dim",
	"text",
	"thinkingText",
	"selectedBg",
	"userMessageBg",
	"userMessageText",
	"customMessageBg",
	"customMessageText",
	"customMessageLabel",
	"toolPendingBg",
	"toolSuccessBg",
	"toolErrorBg",
	"toolTitle",
	"toolOutput",
	"mdHeading",
	"mdLink",
	"mdLinkUrl",
	"mdCode",
	"mdCodeBlock",
	"mdCodeBlockBorder",
	"mdQuote",
	"mdQuoteBorder",
	"mdHr",
	"mdListBullet",
	"toolDiffAdded",
	"toolDiffRemoved",
	"toolDiffContext",
	"syntaxComment",
	"syntaxKeyword",
	"syntaxFunction",
	"syntaxVariable",
	"syntaxString",
	"syntaxNumber",
	"syntaxType",
	"syntaxOperator",
	"syntaxPunctuation",
	"thinkingOff",
	"thinkingMinimal",
	"thinkingLow",
	"thinkingMedium",
	"thinkingHigh",
	"thinkingXhigh",
	"bashMode",
];

const DEFAULT_ANSI = {
	0: "#0f1117",
	1: "#ef4444",
	2: "#22c55e",
	3: "#eab308",
	4: "#3b82f6",
	5: "#a855f7",
	6: "#06b6d4",
	7: "#e5e7eb",
	8: "#6b7280",
	9: "#f87171",
	10: "#4ade80",
	11: "#facc15",
	12: "#60a5fa",
	13: "#c084fc",
	14: "#22d3ee",
	15: "#f9fafb",
};

async function main() {
	const [command, ...argv] = process.argv.slice(2);
	if (command !== "capture-terminal") usage(1);
	const args = parseArgs(argv);
	const name = args.name;
	if (!name) usage(1);
	const out = args.out ?? join("themes", `${name}.json`);
	const ansi = args.ansiJson ? normalizeAnsi(JSON.parse(args.ansiJson)) : await captureAnsi(Number(args.timeout ?? 1200));
	const theme = themeFromAnsi(name, ansi);
	mkdirSync(dirname(out), { recursive: true });
	writeFileSync(out, `${JSON.stringify(theme, null, 2)}\n`, "utf8");
	process.stdout.write(`${out}\n`);
}

function parseArgs(argv) {
	const out = {};
	for (let i = 0; i < argv.length; i++) {
		const arg = argv[i];
		if (arg === "--name") out.name = argv[++i];
		else if (arg === "--out") out.out = argv[++i];
		else if (arg === "--timeout") out.timeout = argv[++i];
		else if (arg === "--ansi-json") out.ansiJson = argv[++i];
		else usage(1);
	}
	return out;
}

async function captureAnsi(timeoutMs) {
	const chunks = [];
	const stdin = process.stdin;
	const wasRaw = Boolean(stdin.isTTY && stdin.setRawMode);
	if (wasRaw) stdin.setRawMode(true);
	stdin.resume();
	stdin.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
	for (let i = 0; i < 16; i++) process.stdout.write(`\x1b]4;${i};?\x07`);
	await new Promise((resolve) => setTimeout(resolve, timeoutMs));
	if (wasRaw) stdin.setRawMode(false);
	stdin.pause();
	return { ...DEFAULT_ANSI, ...parseOsc(Buffer.concat(chunks).toString("utf8")) };
}

function parseOsc(text) {
	const out = {};
	const re = /\x1b\]4;(\d+);([^\x07\x1b]+)(?:\x07|\x1b\\)/g;
	let match;
	while ((match = re.exec(text))) {
		const index = Number(match[1]);
		if (index < 0 || index > 15) continue;
		const color = parseColor(match[2]);
		if (color) out[index] = color;
	}
	return out;
}

function parseColor(value) {
	const hex = value.match(/^#?([0-9a-f]{6})$/i);
	if (hex) return `#${hex[1].toLowerCase()}`;
	const rgb = value.match(/^rgb:([0-9a-f]{2,4})\/([0-9a-f]{2,4})\/([0-9a-f]{2,4})$/i);
	if (!rgb) return undefined;
	return `#${rgb.slice(1).map((part) => part.slice(0, 2).toLowerCase()).join("")}`;
}

function normalizeAnsi(input) {
	const out = { ...DEFAULT_ANSI };
	for (const [key, value] of Object.entries(input)) {
		const index = Number(key);
		const color = typeof value === "string" ? parseColor(value) : undefined;
		if (Number.isInteger(index) && index >= 0 && index <= 15 && color) out[index] = color;
	}
	return out;
}

function themeFromAnsi(name, ansi) {
	const c = (index) => ansi[index] ?? DEFAULT_ANSI[index];
	const colors = {
		accent: c(5),
		border: c(8),
		borderAccent: c(4),
		borderMuted: c(8),
		success: c(2),
		error: c(1),
		warning: c(3),
		muted: c(8),
		dim: c(8),
		text: c(7),
		thinkingText: c(6),
		selectedBg: c(4),
		userMessageBg: c(0),
		userMessageText: c(7),
		customMessageBg: c(0),
		customMessageText: c(7),
		customMessageLabel: c(5),
		toolPendingBg: c(0),
		toolSuccessBg: c(2),
		toolErrorBg: c(1),
		toolTitle: c(15),
		toolOutput: c(7),
		mdHeading: c(5),
		mdLink: c(4),
		mdLinkUrl: c(6),
		mdCode: c(3),
		mdCodeBlock: c(0),
		mdCodeBlockBorder: c(8),
		mdQuote: c(8),
		mdQuoteBorder: c(8),
		mdHr: c(8),
		mdListBullet: c(5),
		toolDiffAdded: c(2),
		toolDiffRemoved: c(1),
		toolDiffContext: c(8),
		syntaxComment: c(8),
		syntaxKeyword: c(5),
		syntaxFunction: c(4),
		syntaxVariable: c(7),
		syntaxString: c(2),
		syntaxNumber: c(3),
		syntaxType: c(6),
		syntaxOperator: c(5),
		syntaxPunctuation: c(7),
		thinkingOff: c(8),
		thinkingMinimal: c(6),
		thinkingLow: c(2),
		thinkingMedium: c(3),
		thinkingHigh: c(1),
		thinkingXhigh: c(5),
		bashMode: c(4),
	};
	for (const token of TOKENS) {
		if (!colors[token]) colors[token] = c(7);
	}
	return {
		$schema: "../schema/pie-ui.schema.json",
		name,
		colors,
	};
}

function usage(code) {
	const text = "usage: fap capture-terminal --name <theme-name> [--out <path>] [--timeout <ms>]\n";
	(code ? process.stderr : process.stdout).write(text);
	process.exit(code);
}

main().catch((error) => {
	process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
	process.exit(1);
});
