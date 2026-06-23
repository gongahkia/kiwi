import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { visibleWidth } from "@earendil-works/pi-tui";
import { applyJsonPatch, applyPresetConfig, effectiveConfig, FOOTER_SEGMENTS, MODE_NAMES, PRESET_NAMES, PRESET_THEMES, validateConfig } from "../extensions/pie-ui/config.ts";
import { applyPie, runPieConfigTool } from "../extensions/pie-ui/index.ts";
import { resolveWriteTarget } from "../extensions/pie-ui/paths.ts";
import { createFooter } from "../extensions/pie-ui/render.ts";

const requiredThemeTokens = [
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

test("project config overrides global after preset materialization", () => {
	const config = effectiveConfig(
		{ preset: "claude-inspired", footer: { separator: " | " } },
		{ preset: "codex-inspired", footer: { segments: ["model", "tokens"] } },
	);
	assert.equal(config.preset, "codex-inspired");
	assert.equal(config.theme, "fried-apple-pie-codex");
	assert.deepEqual(config.footer?.segments, ["model", "tokens"]);
	assert.equal(config.footer?.separator, " | ");
});

test("validation rejects unknown preset and footer segment", () => {
	const result = validateConfig({ preset: "x", footer: { segments: ["model", "bad"] } });
	assert.equal(result.valid, false);
	assert.match(result.errors.join("\n"), /unknown preset/);
	assert.match(result.errors.join("\n"), /unknown footer segment/);
});

test("strict validation rejects unknown keys", () => {
	const loose = validateConfig({ preset: "minimal", extra: true });
	const strict = validateConfig({ preset: "minimal", extra: true }, { strict: true });
	assert.equal(loose.valid, true);
	assert.match(loose.warnings.join("\n"), /unknown key/);
	assert.equal(strict.valid, false);
	assert.match(strict.errors.join("\n"), /unknown key/);
});

test("clean preset application resets preset-owned overrides but keeps mode and strict", () => {
	const clean = applyPresetConfig({ preset: "minimal", mode: "theme-only", strict: true, footer: { segments: ["cost"] } }, "codex-inspired", "clean");
	const merge = applyPresetConfig({ preset: "minimal", mode: "theme-only", strict: true, footer: { segments: ["cost"] } }, "codex-inspired", "merge");
	assert.equal(clean.mode, "theme-only");
	assert.equal(clean.strict, true);
	assert.equal(clean.footer, undefined);
	assert.deepEqual(merge.footer?.segments, ["cost"]);
});

test("json patch replaces nested config and rejects missing replace path", () => {
	const patched = applyJsonPatch({ preset: "minimal", footer: { segments: ["model"] } }, [
		{ op: "replace", path: "/preset", value: "gemini-inspired" },
		{ op: "add", path: "/footer/segments/1", value: "context" },
	]);
	assert.equal(patched.preset, "gemini-inspired");
	assert.deepEqual(patched.footer?.segments, ["model", "context"]);
	assert.throws(() => applyJsonPatch({}, [{ op: "replace", path: "/missing", value: true }]), /patch path missing/);
});

test("every preset maps to a bundled theme", () => {
	const themeFiles = new Set(readdirSync("themes").filter((file) => file.endsWith(".json")));
	for (const preset of PRESET_NAMES) {
		assert.ok(themeFiles.has(`${PRESET_THEMES[preset]}.json`), preset);
	}
});

test("theme files include every required token", () => {
	for (const file of readdirSync("themes").filter((name) => name.endsWith(".json"))) {
		const theme = JSON.parse(readFileSync(join("themes", file), "utf8")) as { name?: string; colors?: Record<string, unknown> };
		assert.equal(typeof theme.name, "string", file);
		for (const token of requiredThemeTokens) assert.ok(theme.colors && token in theme.colors, `${file}: ${token}`);
	}
});

test("write target rejects read-only effective scope and untrusted project scope", () => {
	assert.throws(() => resolveWriteTarget("/tmp/project", true, "effective"), /read-only/);
	assert.throws(() => resolveWriteTarget("/tmp/project", false, "project"), /trusted/);
	assert.equal(resolveWriteTarget("/tmp/project", false).scope, "global");
	assert.equal(resolveWriteTarget("/tmp/project", true).scope, "project");
});

test("schema enums match exported config constants", () => {
	const schema = JSON.parse(readFileSync("schema/pie-ui.schema.json", "utf8")) as {
		properties: {
			preset: { enum: string[] };
			mode: { enum: string[] };
			footer: { properties: { segments: { items: { enum: string[] } } } };
		};
	};
	assert.deepEqual(schema.properties.preset.enum, [...PRESET_NAMES]);
	assert.deepEqual(schema.properties.mode.enum, [...MODE_NAMES]);
	assert.deepEqual(schema.properties.footer.properties.segments.items.enum, [...FOOTER_SEGMENTS]);
});

test("footer render truncates and compact mode shortens labels", () => {
	const ctx = {
		cwd: "/Users/test/src/really/long/project/path",
		model: { id: "very-long-model-name-for-render-test" },
		getContextUsage: () => ({ tokens: 100, contextWindow: 1000, percent: 25 }),
		sessionManager: { getBranch: () => [] },
	} as any;
	const pi = { getThinkingLevel: () => "xhigh" } as any;
	const theme = { fg: (_name: string, text: string) => text, bg: (_name: string, text: string) => text, bold: (text: string) => text };
	const footerData = { getGitBranch: () => "feature/demo", getExtensionStatuses: () => new Map(), onBranchChange: () => () => {} };
	const footer = createFooter(
		{ compact: true, footer: { enabled: true, segments: ["model", "thinking", "cwd", "branch", "status", "context"], separator: " | " } },
		ctx,
		pi,
		{ working: false },
		theme,
		footerData,
	);
	const narrow = footer.render(48)[0];
	const wide = footer.render(140)[0];
	assert.ok(visibleWidth(narrow) <= 48);
	assert.match(wide, /xhigh/);
	assert.doesNotMatch(wide, /think:xhigh/);
	assert.match(wide, /ctx 75%/);
});

test("theme-only mode releases footer and widget surfaces", () => {
	withTempHome((cwd) => {
		writeProjectConfig(cwd, {
			preset: "minimal",
			mode: "theme-only",
			theme: "fried-apple-pie-minimal",
			footer: { enabled: true, segments: ["model"] },
			header: { enabled: true, title: "x" },
			widget: { enabled: true, lines: ["x"] },
			tools: { expanded: true },
		});
		const calls = makeCalls();
		applyPie(makeCtx(cwd, calls), makePi(), { working: false });
		assert.equal(calls.footer, undefined);
		assert.equal(calls.header, undefined);
		assert.equal(calls.widget?.content, undefined);
		assert.deepEqual(calls.toolsExpanded, [false]);
		assert.deepEqual(calls.themes, ["fried-apple-pie-minimal"]);
	});
});

test("pie_config set_preset clean writes project config", async () => {
	await withTempHomeAsync(async (cwd) => {
		writeProjectConfig(cwd, { preset: "minimal", mode: "theme-only", footer: { segments: ["cost"] } });
		const calls = makeCalls();
		const result = await runPieConfigTool({ action: "set_preset", preset: "codex-inspired", applyMode: "clean", scope: "project" } as any, makeCtx(cwd, calls), makePi(), { working: false });
		assert.equal(result.isError, false);
		const written = JSON.parse(readFileSync(join(cwd, ".pi", "pie-ui.json"), "utf8"));
		assert.equal(written.preset, "codex-inspired");
		assert.equal(written.theme, "fried-apple-pie-codex");
		assert.equal(written.mode, "theme-only");
		assert.equal(written.footer, undefined);
	});
});

test("pie_config convenience actions update footer, compact, and theme", async () => {
	await withTempHomeAsync(async (cwd) => {
		writeProjectConfig(cwd, { preset: "minimal", compact: true, footer: { segments: ["model"] } });
		const calls = makeCalls();
		const ctx = makeCtx(cwd, calls);
		await runPieConfigTool({ action: "set_footer_segments", footerSegments: ["model", "cost"], scope: "project" } as any, ctx, makePi(), { working: false });
		await runPieConfigTool({ action: "toggle_compact", scope: "project" } as any, ctx, makePi(), { working: false });
		await runPieConfigTool({ action: "set_theme", theme: "fried-apple-pie-gemini", scope: "project" } as any, ctx, makePi(), { working: false });
		const written = JSON.parse(readFileSync(join(cwd, ".pi", "pie-ui.json"), "utf8"));
		assert.deepEqual(written.footer.segments, ["model", "cost"]);
		assert.equal(written.compact, false);
		assert.equal(written.theme, "fried-apple-pie-gemini");
	});
});

test("package metadata and preview assets are publish-ready", () => {
	const pkg = JSON.parse(readFileSync("package.json", "utf8"));
	assert.equal(pkg.license, "MIT");
	assert.ok(pkg.repository?.url);
	assert.ok(pkg.homepage);
	assert.ok(pkg.bugs?.url);
	assert.match(pkg.pi.image, /^https:\/\/raw\.githubusercontent\.com\//);
	const png = readFileSync("assets/fried-apple-pie-gallery.png");
	assert.equal(png.readUInt32BE(16), 1200);
	assert.equal(png.readUInt32BE(20), 740);
});

function writeProjectConfig(cwd: string, config: unknown): void {
	mkdirSync(join(cwd, ".pi"), { recursive: true });
	writeFileSync(join(cwd, ".pi", "pie-ui.json"), `${JSON.stringify(config, null, 2)}\n`, "utf8");
}

function withTempHome<T>(fn: (cwd: string) => T): T {
	const oldHome = process.env.HOME;
	const root = mkdtempSync(join(tmpdir(), "fried-apple-pie-"));
	process.env.HOME = root;
	try {
		return fn(root);
	} finally {
		process.env.HOME = oldHome;
	}
}

async function withTempHomeAsync<T>(fn: (cwd: string) => Promise<T>): Promise<T> {
	const oldHome = process.env.HOME;
	const root = mkdtempSync(join(tmpdir(), "fried-apple-pie-"));
	process.env.HOME = root;
	try {
		return await fn(root);
	} finally {
		process.env.HOME = oldHome;
	}
}

function makeCalls() {
	return {
		themes: [] as string[],
		toolsExpanded: [] as boolean[],
		header: "unset" as unknown,
		footer: "unset" as unknown,
		widget: undefined as { content: string[] | undefined; options: unknown } | undefined,
	};
}

function makeCtx(cwd: string, calls: ReturnType<typeof makeCalls>): any {
	return {
		cwd,
		mode: "tui",
		hasUI: true,
		model: { id: "test-model" },
		sessionManager: { getBranch: () => [] },
		isProjectTrusted: () => true,
		getContextUsage: () => ({ tokens: 100, contextWindow: 1000, percent: 10 }),
		ui: {
			notify() {},
			setTheme(name: string) {
				calls.themes.push(name);
				return { success: true };
			},
			setToolsExpanded(value: boolean) {
				calls.toolsExpanded.push(value);
			},
			setHiddenThinkingLabel() {},
			setWorkingVisible() {},
			setWorkingMessage() {},
			setWorkingIndicator() {},
			setWidget(_key: string, content: string[] | undefined, options: unknown) {
				calls.widget = { content, options };
			},
			setHeader(factory: unknown) {
				calls.header = factory;
			},
			setFooter(factory: unknown) {
				calls.footer = factory;
			},
			getAllThemes: () => [{ name: "fried-apple-pie-minimal" }, { name: "fried-apple-pie-codex" }],
		},
	};
}

function makePi(): any {
	return {
		getThinkingLevel: () => "xhigh",
		getCommands: () => [],
	};
}
