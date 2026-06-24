import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { visibleWidth } from "@earendil-works/pi-tui";
import { applyJsonPatch, applyPresetConfig, effectiveConfig, FOOTER_SEGMENTS, materializeConfig, MODE_NAMES, PRESET_NAMES, PRESET_THEMES, validateConfig, WHEN_RULES } from "../extensions/pie-ui/config.ts";
import { LAYER_NAMES } from "../extensions/pie-ui/layers.ts";
import { applyEffectiveConfig, applyPie, diffLines, historyLines, maybeWarnContext, runPieConfigTool } from "../extensions/pie-ui/index.ts";
import { appendHistory, historyPath, popHistory, readConfigFile, readHistory, resolveWriteTarget } from "../extensions/pie-ui/paths.ts";
import { createFooter, shouldRenderSegment } from "../extensions/pie-ui/render.ts";

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
			layers: { items: { enum: string[] } };
			footer: { properties: { segments: { items: { oneOf: Array<{ enum?: string[]; properties?: { id?: { enum?: string[] }; when?: { enum?: string[] } } }> } } } };
		};
	};
	assert.deepEqual(schema.properties.preset.enum, [...PRESET_NAMES]);
	assert.deepEqual(schema.properties.mode.enum, [...MODE_NAMES]);
	assert.deepEqual([...schema.properties.layers.items.enum].sort(), [...LAYER_NAMES].sort());
	const segmentItems = schema.properties.footer.properties.segments.items;
	const stringForm = segmentItems.oneOf.find((branch) => Array.isArray(branch.enum));
	const objectForm = segmentItems.oneOf.find((branch) => branch.properties);
	assert.deepEqual(stringForm?.enum, [...FOOTER_SEGMENTS]);
	assert.deepEqual(objectForm?.properties?.id?.enum, [...FOOTER_SEGMENTS]);
	assert.deepEqual(objectForm?.properties?.when?.enum, [...WHEN_RULES]);
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

test("persona validation accepts known and rejects unknown", () => {
	const ok = validateConfig({ preset: "minimal", persona: "terse" });
	const bad = validateConfig({ preset: "minimal", persona: "not-a-real-persona" });
	const wrongType = validateConfig({ preset: "minimal", persona: 42 as unknown });
	assert.equal(ok.valid, true);
	assert.equal(bad.valid, false);
	assert.match(bad.errors.join("\n"), /unknown persona/);
	assert.equal(wrongType.valid, false);
	assert.match(wrongType.errors.join("\n"), /persona must be a string/);
});

test("applyPie wires persona spinner and verb into setWorkingIndicator and setWorkingMessage", () => {
	withTempHome((cwd) => {
		writeProjectConfig(cwd, { preset: "codex-inspired", persona: "startrek" });
		const calls = makeCalls();
		applyPie(makeCtx(cwd, calls), makePi(), { working: false });
		const lastIndicator = calls.workingIndicator.at(-1);
		const lastMessage = calls.workingMessage.at(-1);
		assert.ok(lastIndicator?.frames?.length, "startrek persona must produce spinner frames");
		assert.equal(typeof lastMessage, "string");
		assert.match(String(lastMessage), /warp drive|diagnostics|Hailing/);
	});
});

test("applyPie falls back to preset default persona when config.persona is unset", () => {
	withTempHome((cwd) => {
		writeProjectConfig(cwd, { preset: "codex-inspired" });
		const calls = makeCalls();
		applyPie(makeCtx(cwd, calls), makePi(), { working: false });
		// codex-inspired defaults to arc persona; spinner frames must be set
		assert.ok(calls.workingIndicator.at(-1)?.frames?.length);
	});
});

test("conditional footer segments accept object form with when rule", () => {
	const ok = validateConfig({
		preset: "minimal",
		footer: { segments: ["model", { id: "cost", when: "context>70" }, { id: "branch", when: "git-repo" }] },
	});
	assert.equal(ok.valid, true);
	const badId = validateConfig({ preset: "minimal", footer: { segments: [{ id: "nope" } as unknown as never] } });
	assert.equal(badId.valid, false);
	assert.match(badId.errors.join("\n"), /unknown footer segment/);
	const badWhen = validateConfig({ preset: "minimal", footer: { segments: [{ id: "cost", when: "always-on" } as unknown as never] } });
	assert.equal(badWhen.valid, false);
	assert.match(badWhen.errors.join("\n"), /unknown footer segment when rule/);
});

test("shouldRenderSegment evaluates when rules against ctx and footerData", () => {
	const footerWithBranch = { getGitBranch: () => "main", getExtensionStatuses: () => new Map(), onBranchChange: () => () => {} };
	const footerNoBranch = { getGitBranch: () => null, getExtensionStatuses: () => new Map(), onBranchChange: () => () => {} };
	const trusted = { isProjectTrusted: () => true, getContextUsage: () => ({ tokens: 100, contextWindow: 1000, percent: 80 }), sessionManager: { getBranch: () => [] } } as any;
	const untrusted = { isProjectTrusted: () => false, getContextUsage: () => ({ tokens: 100, contextWindow: 1000, percent: 10 }), sessionManager: { getBranch: () => [] } } as any;
	assert.equal(shouldRenderSegment(undefined, trusted, footerWithBranch), true);
	assert.equal(shouldRenderSegment("always", trusted, footerWithBranch), true);
	assert.equal(shouldRenderSegment("git-repo", trusted, footerWithBranch), true);
	assert.equal(shouldRenderSegment("git-repo", trusted, footerNoBranch), false);
	assert.equal(shouldRenderSegment("trusted-project", trusted, footerWithBranch), true);
	assert.equal(shouldRenderSegment("trusted-project", untrusted, footerWithBranch), false);
	assert.equal(shouldRenderSegment("context>70", trusted, footerWithBranch), true);
	assert.equal(shouldRenderSegment("context>70", untrusted, footerWithBranch), false);
	assert.equal(shouldRenderSegment("context>90", trusted, footerWithBranch), false);
});

test("createFooter respects conditional segments and skips when rules that fail", () => {
	const ctx = {
		cwd: "/Users/test/repo",
		model: { id: "m" },
		isProjectTrusted: () => true,
		getContextUsage: () => ({ tokens: 100, contextWindow: 1000, percent: 50 }),
		sessionManager: { getBranch: () => [] },
	} as any;
	const pi = { getThinkingLevel: () => "low" } as any;
	const theme = { fg: (_n: string, t: string) => t, bg: (_n: string, t: string) => t, bold: (t: string) => t };
	const footerData = { getGitBranch: () => null, getExtensionStatuses: () => new Map(), onBranchChange: () => () => {} };
	const footer = createFooter(
		{
			compact: true,
			footer: {
				enabled: true,
				segments: ["model", { id: "branch", when: "git-repo" }, { id: "cost", when: "context>90" }, { id: "preset", when: "always" }],
				separator: " | ",
			},
			preset: "minimal",
		},
		ctx,
		pi,
		{ working: false },
		theme,
		footerData,
	);
	const line = footer.render(120)[0];
	assert.match(line, /m/);
	assert.match(line, /minimal/);
	assert.doesNotMatch(line, /\$/);
	assert.equal(line.includes("main"), false);
});

test("diffLines reports no change for identical configs and changes for distinct presets", () => {
	const minimal = materializeConfig({ preset: "minimal" });
	const codex = materializeConfig(applyPresetConfig({ preset: "minimal" }, "codex-inspired", "clean"));
	const same = diffLines(minimal, minimal);
	const cross = diffLines(minimal, codex);
	assert.deepEqual(same, ["no effective change"]);
	assert.match(cross.join("\n"), /preset:/);
	assert.match(cross.join("\n"), /theme:/);
	assert.match(cross.join("\n"), /\d+ keys? changed/);
});

test("layers apply between preset and user config; user config wins on conflict", () => {
	// codex-inspired uses theme fried-apple-pie-codex. theme:gemini layer overrides to gemini.
	const codexThenGemini = materializeConfig({ preset: "codex-inspired", layers: ["theme:gemini"] });
	assert.equal(codexThenGemini.theme, "fried-apple-pie-gemini");
	// user raw config overrides a layer's value
	const userWins = materializeConfig({ preset: "codex-inspired", layers: ["theme:gemini"], theme: "fried-apple-pie-nord" });
	assert.equal(userWins.theme, "fried-apple-pie-nord");
	// footer layer compounds: footer:powerline sets segments, footer:none then disables
	const disabled = materializeConfig({ preset: "minimal", layers: ["footer:powerline", "footer:none"] });
	assert.equal(disabled.footer?.enabled, false);
});

test("layer validation warns by default and errors in strict for unknown layers", () => {
	const loose = validateConfig({ preset: "minimal", layers: ["theme:codex", "made-up:layer"] });
	const strict = validateConfig({ preset: "minimal", layers: ["theme:codex", "made-up:layer"] }, { strict: true });
	assert.equal(loose.valid, true);
	assert.match(loose.warnings.join("\n"), /unknown layer/);
	assert.equal(strict.valid, false);
	assert.match(strict.errors.join("\n"), /unknown layer/);
});

test("maybeWarnContext fires mid+high notifications once per session and respects opt-out", () => {
	const notifies: Array<{ message: string; level: string }> = [];
	const ui = { notify: (message: string, level: string) => notifies.push({ message, level }) } as any;
	const makeWarnedCtx = (percent: number) => ({ ui, getContextUsage: () => ({ tokens: 100, contextWindow: 1000, percent }) }) as any;
	const warned = { mid: false, high: false };
	const state = { working: false, lastConfig: { preset: "minimal" as const } };
	maybeWarnContext(makeWarnedCtx(40), state, warned);
	assert.equal(notifies.length, 0, "no warnings below threshold");
	maybeWarnContext(makeWarnedCtx(75), state, warned);
	assert.equal(notifies.length, 1, "70% fires once");
	maybeWarnContext(makeWarnedCtx(75), state, warned);
	assert.equal(notifies.length, 1, "70% does not refire");
	maybeWarnContext(makeWarnedCtx(95), state, warned);
	assert.equal(notifies.length, 2, "90% fires once");
	maybeWarnContext(makeWarnedCtx(95), state, warned);
	assert.equal(notifies.length, 2, "90% does not refire");

	// opt-out via config
	const warned2 = { mid: false, high: false };
	const state2 = { working: false, lastConfig: { preset: "minimal" as const, notifications: { contextWarnings: false } } };
	const optedNotifies: Array<{ message: string }> = [];
	const optedUi = { notify: (message: string) => optedNotifies.push({ message }) } as any;
	const optedCtx = { ui: optedUi, getContextUsage: () => ({ tokens: 100, contextWindow: 1000, percent: 95 }) } as any;
	maybeWarnContext(optedCtx, state2, warned2);
	assert.equal(optedNotifies.length, 0, "opt-out suppresses warnings");
});

test("status-only mode releases header/footer/widget and writes setStatus with preset + ctx", () => {
	withTempHome((cwd) => {
		writeProjectConfig(cwd, { preset: "codex-inspired", mode: "status-only" });
		const calls = makeCalls();
		applyPie(makeCtx(cwd, calls), makePi(), { working: false });
		assert.equal(calls.footer, undefined, "footer should be released");
		assert.equal(calls.header, undefined, "header should be released");
		assert.equal(calls.widget?.content, undefined, "widget should be released");
		assert.ok(calls.status.length >= 1, "setStatus should be called at least once");
		const last = calls.status.at(-1);
		assert.equal(last?.key, "fried-apple-pie");
		assert.match(String(last?.text), /codex-inspired/);
		assert.match(String(last?.text), /ctx \d+%/);
	});
});

test("non-status-only modes clear the status surface (no leak)", () => {
	withTempHome((cwd) => {
		writeProjectConfig(cwd, { preset: "minimal", mode: "full" });
		const calls = makeCalls();
		applyPie(makeCtx(cwd, calls), makePi(), { working: false });
		const last = calls.status.at(-1);
		assert.equal(last?.key, "fried-apple-pie");
		assert.equal(last?.text, undefined);
	});
});

test("import flow: readConfigFile parses arbitrary path and validateConfig catches malformed input", () => {
	const dir = mkdtempSync(join(tmpdir(), "pie-import-"));
	const valid = join(dir, "valid.json");
	writeFileSync(valid, JSON.stringify({ preset: "codex-inspired" }));
	const ok = readConfigFile(valid);
	assert.equal(ok?.preset, "codex-inspired");
	const v = validateConfig(materializeConfig(ok));
	assert.equal(v.valid, true);

	const invalidPreset = join(dir, "invalid.json");
	writeFileSync(invalidPreset, JSON.stringify({ preset: "not-a-preset" }));
	const bad = readConfigFile(invalidPreset);
	const bv = validateConfig(materializeConfig(bad));
	assert.equal(bv.valid, false);
	assert.match(bv.errors.join("\n"), /unknown preset/);

	const garbage = join(dir, "garbage.json");
	writeFileSync(garbage, "not-json");
	const errs: string[] = [];
	const parsed = readConfigFile(garbage, errs);
	assert.equal(parsed, undefined);
	assert.equal(errs.length, 1);
});

test("appendHistory + popHistory + readHistory round-trip", () => {
	withTempHome(() => {
		assert.deepEqual(readHistory(), []);
		appendHistory({ ts: 1, scope: "global", path: "/tmp/x", previous: { preset: "minimal" }, next: { preset: "codex-inspired" } });
		appendHistory({ ts: 2, scope: "global", path: "/tmp/x", previous: { preset: "codex-inspired" }, next: { preset: "claude-inspired" } });
		const all = readHistory();
		assert.equal(all.length, 2);
		const popped = popHistory();
		assert.equal(popped?.next.preset, "claude-inspired");
		assert.equal(readHistory().length, 1);
		assert.equal(existsSync(historyPath()), true);
	});
});

test("history is capped at 50 entries", () => {
	withTempHome(() => {
		for (let i = 0; i < 60; i++) {
			appendHistory({ ts: i, scope: "global", path: "/tmp/x", previous: { preset: "minimal" }, next: { preset: "codex-inspired" } });
		}
		const entries = readHistory();
		assert.equal(entries.length, 50);
		// rolling window keeps the most recent entries
		assert.equal(entries[0].ts, 10);
		assert.equal(entries.at(-1)?.ts, 59);
	});
});

test("historyLines renders count, scope, and arrows; handles empty", () => {
	const empty = historyLines([]);
	assert.match(empty.join("\n"), /history empty/);
	const lines = historyLines([
		{ ts: Date.UTC(2026, 5, 1, 12, 0, 0), scope: "global", path: "/tmp/g.json", previous: { preset: "minimal" }, next: { preset: "codex-inspired" } },
		{ ts: Date.UTC(2026, 5, 1, 13, 0, 0), scope: "project", path: "/tmp/p.json", previous: { preset: "codex-inspired" }, next: { preset: "dracula" } },
	]);
	assert.match(lines.join("\n"), /2 entries/);
	assert.match(lines.join("\n"), /minimal -> codex-inspired/);
	assert.match(lines.join("\n"), /codex-inspired -> dracula/);
	assert.match(lines.join("\n"), /\[global\]/);
	assert.match(lines.join("\n"), /\[project\]/);
});

test("applyEffectiveConfig applies transient config without writing to disk (gallery contract)", () => {
	withTempHome((cwd) => {
		const calls = makeCalls();
		const transient = materializeConfig(applyPresetConfig({ preset: "minimal" }, "dracula", "clean"));
		applyEffectiveConfig(makeCtx(cwd, calls), makePi(), { working: false }, transient);
		assert.deepEqual(calls.themes, ["fried-apple-pie-dracula"]);
		assert.equal(existsSync(join(cwd, ".pi", "pie-ui.json")), false, "gallery cycle must not write to disk");
		assert.equal(existsSync(join(cwd, ".pi", "agent", "pie-ui.json")), false, "gallery cycle must not write to disk");
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
		workingMessage: [] as Array<string | undefined>,
		workingIndicator: [] as Array<{ frames?: string[]; intervalMs?: number } | undefined>,
		status: [] as Array<{ key: string; text?: string }>,
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
			setWorkingMessage(value?: string) {
				calls.workingMessage.push(value);
			},
			setWorkingIndicator(value?: { frames?: string[]; intervalMs?: number }) {
				calls.workingIndicator.push(value);
			},
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
			setStatus(key: string, text?: string) {
				calls.status.push({ key, text });
			},
		},
	};
}

function makePi(): any {
	return {
		getThinkingLevel: () => "xhigh",
		getCommands: () => [],
	};
}
