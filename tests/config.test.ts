import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { visibleWidth } from "@earendil-works/pi-tui";
import { pieAutocompleteSuggestions } from "../extensions/pie-ui/autocomplete.ts";
import { BANNERS } from "../extensions/pie-ui/banners.ts";
import { applyJsonPatch, applyPresetConfig, effectiveConfig, FOOTER_SEGMENTS, materializeConfig, MODE_NAMES, PRESET_NAMES, PRESET_THEMES, TOOL_RENDER_STYLES, validateConfig, WHEN_RULES } from "../extensions/pie-ui/config.ts";
import { LAYER_NAMES } from "../extensions/pie-ui/layers.ts";
import friedApplePieExtension, { applyEffectiveConfig, applyPie, captureDependencyLines, diffLines, editJsonConfig, emitPieEvent, historyLines, importConfig, launchPresetOverride, maybeWarnContext, personaSystemPrompt, PIE_HISTORY_TYPE, PIE_LEADER_SHORTCUTS, PIE_WELCOME_TYPE, recordHistory, rotateWorkingVerb, runPieConfigTool, shareTimestamp, shortcutLines, tapePathFor, welcomeConflictLines, welcomeMessageForSession, writeShareBundle } from "../extensions/pie-ui/index.ts";
import { appendHistory, historyPath, popHistory, readConfigFile, readHistory, resolveWriteTarget } from "../extensions/pie-ui/paths.ts";
import { createFooter, PIE_SHORTCUT_ACTIONS, shouldRenderSegment } from "../extensions/pie-ui/render.ts";
import { defineFriedApplePiePreset } from "../extensions/pie-ui/sdk.ts";
import { analyticsStatus, hashedInstallId, postStats, statsPayload } from "../extensions/pie-ui/stats.ts";
import { registerPresetToolRenderers, RENDERED_TOOL_NAMES, renderToolCall, renderToolResult } from "../extensions/pie-ui/tool-renderers.ts";

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
			tools: { properties: { renderStyle: { enum: string[] } } };
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
	assert.deepEqual(schema.properties.tools.properties.renderStyle.enum, [...TOOL_RENDER_STYLES]);
});

test("tool render style validates and every preset declares one", () => {
	const ok = validateConfig({ preset: "minimal", tools: { renderStyle: "dense" } });
	const bad = validateConfig({ preset: "minimal", tools: { renderStyle: "wide" } });
	assert.equal(ok.valid, true);
	assert.equal(bad.valid, false);
	assert.match(bad.errors.join("\n"), /unknown tool render style/);
	for (const preset of PRESET_NAMES) {
		const style = materializeConfig({ preset }).tools?.renderStyle;
		assert.ok(style && TOOL_RENDER_STYLES.includes(style), `${preset}: missing render style`);
	}
});

test("welcome config validates custom banners", () => {
	const ok = validateConfig({ preset: "minimal", welcome: { enabled: true, banner: ["pie", "ready"] } });
	const badEnabled = validateConfig({ preset: "minimal", welcome: { enabled: "yes" } });
	const badBanner = validateConfig({ preset: "minimal", welcome: { banner: ["pie", 1] } });
	assert.equal(ok.valid, true);
	assert.equal(badEnabled.valid, false);
	assert.match(badEnabled.errors.join("\n"), /welcome.enabled/);
	assert.equal(badBanner.valid, false);
	assert.match(badBanner.errors.join("\n"), /welcome.banner/);
});

test("analytics config validates opt-in shape", () => {
	const ok = validateConfig({ preset: "minimal", analytics: { enabled: true, endpoint: "https://stats.example.test" } });
	const badEnabled = validateConfig({ preset: "minimal", analytics: { enabled: "yes" } });
	const badEndpoint = validateConfig({ preset: "minimal", analytics: { endpoint: 123 } });
	assert.equal(ok.valid, true);
	assert.equal(badEnabled.valid, false);
	assert.match(badEnabled.errors.join("\n"), /analytics.enabled/);
	assert.equal(badEndpoint.valid, false);
	assert.match(badEndpoint.errors.join("\n"), /analytics.endpoint/);
});

test("every preset has a bundled startup banner", () => {
	assert.deepEqual(Object.keys(BANNERS).sort(), [...PRESET_NAMES].sort());
	for (const preset of PRESET_NAMES) {
		assert.ok(BANNERS[preset].length > 0, preset);
		for (const line of BANNERS[preset]) {
			assert.equal(typeof line, "string", preset);
			assert.equal(/^[\x20-\x7e]*$/.test(line), true, `${preset}: non-ascii banner line`);
		}
	}
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

test("turn_start verb rotation advances through persona verbs", () => {
	withTempHome((cwd) => {
		writeProjectConfig(cwd, { preset: "codex-inspired", persona: "arc" });
		const calls = makeCalls();
		const ctx = makeCtx(cwd, calls);
		const state = { working: false };
		applyPie(ctx, makePi(), state);
		assert.equal(calls.workingMessage.at(-1), "Working");
		assert.equal(rotateWorkingVerb(ctx, state), "Reasoning");
		assert.equal(rotateWorkingVerb(ctx, state), "Working");
		assert.equal(rotateWorkingVerb(ctx, state), "Reasoning");
	});
});

test("startup welcome message respects reason, disable flag, and custom banner", () => {
	const custom = welcomeMessageForSession("startup", materializeConfig({ preset: "minimal", welcome: { banner: ["custom pie"] } }));
	assert.equal(custom?.customType, PIE_WELCOME_TYPE);
	assert.equal(custom?.display, true);
	assert.deepEqual(custom?.details.lines, ["custom pie"]);
	assert.equal(welcomeMessageForSession("reload", materializeConfig({ preset: "minimal" })), undefined);
	assert.equal(welcomeMessageForSession("fork", materializeConfig({ preset: "minimal" })), undefined);
	assert.equal(welcomeMessageForSession("startup", materializeConfig({ preset: "minimal", welcome: { enabled: false } })), undefined);
});

test("welcomeConflictLines warns only when powerline splash can overlap", () => {
	const enabled = materializeConfig({ preset: "minimal" });
	const disabled = materializeConfig({ preset: "minimal", welcome: { enabled: false } });
	assert.match(welcomeConflictLines(["powerline-footer"], enabled).join("\n"), /startup splash/);
	assert.match(welcomeConflictLines(["footer"], enabled).join("\n"), /startup splash/);
	assert.deepEqual(welcomeConflictLines(["powerline-footer"], disabled), []);
	assert.deepEqual(welcomeConflictLines(["tool-display"], enabled), []);
});

test("explicit working.message disables persona verb rotation", () => {
	withTempHome((cwd) => {
		const calls = makeCalls();
		const ctx = makeCtx(cwd, calls);
		const state = { working: false };
		applyEffectiveConfig(ctx, makePi(), state, materializeConfig({ preset: "codex-inspired", persona: "arc", working: { message: "Pinned" } }));
		const before = calls.workingMessage.length;
		assert.equal(calls.workingMessage.at(-1), "Pinned");
		assert.equal(rotateWorkingVerb(ctx, state), undefined);
		assert.equal(calls.workingMessage.length, before);
	});
});

test("persona system prompt suffix applies only when configured", () => {
	const base = "base prompt";
	const terse = personaSystemPrompt(base, materializeConfig({ preset: "minimal", persona: "terse" }));
	assert.match(terse ?? "", /Respond tersely/);
	assert.match(terse ?? "", /base prompt/);
	assert.equal(personaSystemPrompt(terse ?? "", materializeConfig({ preset: "minimal", persona: "terse" })), undefined);
	assert.equal(personaSystemPrompt(base, materializeConfig({ preset: "minimal", persona: "startrek" })), undefined);
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

test("every preset has a generated tape file (for /pie capture and vhs CI)", () => {
	for (const preset of PRESET_NAMES) {
		const tape = tapePathFor(preset);
		assert.equal(existsSync(tape), true, `tape missing for ${preset}: ${tape}`);
		const body = readFileSync(tape, "utf8");
		assert.ok(body.includes(`/pie preset ${preset}`), `tape ${preset} missing preset command`);
		assert.ok(body.includes(`Output assets/preview-${preset}.gif`), `tape ${preset} missing output`);
	}
});

test("every preset has a captured preview gif", () => {
	for (const preset of PRESET_NAMES) {
		const preview = join("assets", `preview-${preset}.gif`);
		assert.equal(existsSync(preview), true, `preview missing for ${preset}: ${preview}`);
		const body = readFileSync(preview);
		assert.ok(body.length > 1024, `preview too small for ${preset}`);
		assert.match(body.subarray(0, 6).toString("ascii"), /^GIF8[79]a$/);
	}
});

test("captureDependencyLines reports missing capture tools", () => {
	const paths: Record<string, string | undefined> = {
		vhs: "/opt/homebrew/bin/vhs",
		ttyd: undefined,
		ffmpeg: "/opt/homebrew/bin/ffmpeg",
	};
	const lines = captureDependencyLines((name) => paths[name]);
	assert.match(lines.join("\n"), /capture dependency: vhs ok/);
	assert.match(lines.join("\n"), /capture dependency: ttyd missing/);
	assert.match(lines.join("\n"), /capture dependency: ffmpeg ok/);
	assert.match(lines.join("\n"), /capture unavailable: install ttyd on PATH/);
});

test("shortcut leader registration and doctor lines cover every follow-up", () => {
	const shortcuts: Array<{ key: string; description?: string }> = [];
	const flags: Array<{ name: string; type: string; default?: string | boolean }> = [];
	const pi = {
		on() {},
		registerMessageRenderer() {},
		registerCommand() {},
		registerTool() {},
		registerFlag(name: string, options: { type: string; default?: string | boolean }) {
			flags.push({ name, type: options.type, default: options.default });
		},
		registerShortcut(key: string, options: { description?: string }) {
			shortcuts.push({ key, description: options.description });
		},
	} as any;
	friedApplePieExtension(pi);
	assert.deepEqual(flags, [{ name: "pie-preset", type: "string", default: "" }]);
	assert.deepEqual(shortcuts.map((shortcut) => shortcut.key), [...PIE_LEADER_SHORTCUTS]);
	assert.ok(shortcuts.every((shortcut) => shortcut.description === "Fried Apple Pie leader (p/g/s/e/d/c)"));
	const lines = shortcutLines();
	for (const action of PIE_SHORTCUT_ACTIONS) {
		assert.ok(lines.some((line) => line.includes(`${PIE_LEADER_SHORTCUTS[0]} ${action.key}`) && line.includes(action.label)), action.id);
	}
	assert.match(lines.join("\n"), /app\.model\.cycleForward/);
});

test("pie-preset flag applies a transient launch preset without writing config", () => {
	withTempHome((cwd) => {
		writeProjectConfig(cwd, { preset: "minimal" });
		const calls = makeCalls();
		const ctx = makeCtx(cwd, calls);
		const pi = { ...makePi(), getFlag: (name: string) => (name === "pie-preset" ? "codex-inspired" : undefined) } as any;
		const override = launchPresetOverride(ctx, pi);
		assert.equal(override?.preset, "codex-inspired");
		applyPie(ctx, pi, { working: false }, override);
		assert.equal(calls.themes.at(-1), "fried-apple-pie-codex");
		const written = JSON.parse(readFileSync(join(cwd, ".pi", "pie-ui.json"), "utf8"));
		assert.equal(written.preset, "minimal");
	});
});

test("writeShareBundle writes effective config, payload, and preview asset", () => {
	withTempHome((cwd) => {
		const ts = Date.UTC(2026, 5, 24, 1, 2, 3);
		const config = materializeConfig({ preset: "codex-inspired" });
		const bundle = writeShareBundle(config, cwd, ts);
		assert.equal(bundle.dir.endsWith(join("assets", "share", "20260624T010203Z")), true);
		assert.equal(shareTimestamp(ts), "20260624T010203Z");
		assert.equal(existsSync(bundle.configPath), true);
		assert.equal(existsSync(bundle.payloadPath), true);
		assert.equal(bundle.screenshotPath ? existsSync(bundle.screenshotPath) : false, true);
		const writtenConfig = JSON.parse(readFileSync(bundle.configPath, "utf8"));
		const payload = JSON.parse(readFileSync(bundle.payloadPath, "utf8"));
		assert.equal(writtenConfig.preset, "codex-inspired");
		assert.equal(payload.package, "fried-apple-pie");
		assert.equal(payload.config.preset, "codex-inspired");
		assert.equal(payload.screenshotPath, "screenshot.gif");
	});
});

test("tool renderers expose distinct styles and preserve built-in executes", () => {
	const theme = { fg: (_name: string, text: string) => text, bg: (_name: string, text: string) => `[${text}]`, bold: (text: string) => `*${text}*` };
	const calls = TOOL_RENDER_STYLES.map((style) => renderToolCall(style, "bash", { command: "echo hello" }, theme, { executionStarted: true }).render(80)[0]);
	assert.equal(new Set(calls).size, TOOL_RENDER_STYLES.length);
	const result = renderToolResult(
		"dense",
		"bash",
		{ content: [{ type: "text", text: "hello" }], details: undefined } as any,
		{ expanded: false, isPartial: false },
		theme,
		{ isError: false },
	).render(80).join("\n");
	assert.match(result, /hello/);

	const tools: any[] = [];
	registerPresetToolRenderers({ registerTool: (tool: unknown) => tools.push(tool) } as any, process.cwd(), () => "dense");
	assert.deepEqual(tools.map((tool) => tool.name), [...RENDERED_TOOL_NAMES]);
	assert.ok(tools.every((tool) => typeof tool.execute === "function" && tool.parameters && typeof tool.renderCall === "function" && typeof tool.renderResult === "function"));
});

test("pie autocomplete suggests config keys and enum values", () => {
	const keyLine = '  "pre';
	const key = pieAutocompleteSuggestions(["{", '  "preset": "minimal",', keyLine], 2, keyLine.length);
	assert.ok(key?.items.some((item) => item.label === "preset"));
	const presetLine = '  "preset": "co';
	const preset = pieAutocompleteSuggestions(["{", presetLine], 1, presetLine.length);
	assert.ok(preset?.items.some((item) => item.label === "codex-inspired" && item.value === '"codex-inspired"'));
	const styleLine = '    "renderStyle": "d';
	const style = pieAutocompleteSuggestions(["{", '  "tools": {', styleLine], 2, styleLine.length);
	assert.ok(style?.items.some((item) => item.label === "dense"));
});

test("editJsonConfig applies valid editor JSON live", async () => {
	await withTempHomeAsync(async (cwd) => {
		writeProjectConfig(cwd, { preset: "minimal" });
		const calls = makeCalls();
		const ctx = makeCtx(cwd, calls);
		ctx.hasUI = false;
		ctx.ui.editor = async (_title: string, prefill?: string) => {
			assert.match(prefill ?? "", /"preset": "minimal"/);
			return JSON.stringify({ preset: "codex-inspired", theme: "fried-apple-pie-codex", tools: { renderStyle: "dense" } }, null, 2);
		};
		ctx.ui.confirm = async () => true;
		await editJsonConfig(ctx, makePi(), { working: false });
		const written = JSON.parse(readFileSync(join(cwd, ".pi", "pie-ui.json"), "utf8"));
		assert.equal(written.preset, "codex-inspired");
		assert.equal(written.tools.renderStyle, "dense");
		assert.equal(calls.themes.at(-1), "fried-apple-pie-codex");
	});
});

test("emitPieEvent fires on pi.events bus when present and no-ops when absent", () => {
	const seen: Array<{ name: string; payload: unknown }> = [];
	const piWithBus = { events: { emit: (name: string, payload: unknown) => seen.push({ name, payload }) } } as any;
	emitPieEvent(piWithBus, "pie:preset-changed", { from: "minimal", to: "codex-inspired", scope: "global", path: "/tmp/x", ts: 1 });
	assert.equal(seen.length, 1);
	assert.equal(seen[0].name, "pie:preset-changed");
	assert.deepEqual(seen[0].payload, { from: "minimal", to: "codex-inspired", scope: "global", path: "/tmp/x", ts: 1 });
	// no events bus -> no throw, no record
	const piWithoutBus = {} as any;
	emitPieEvent(piWithoutBus, "pie:mode-changed", { to: "theme-only", scope: "project", path: "/tmp/y", ts: 2 });
	assert.equal(seen.length, 1);
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

test("importConfig fetches URL JSON with pi.exec curl and applies it", async () => {
	await withTempHomeAsync(async (cwd) => {
		writeProjectConfig(cwd, { preset: "minimal" });
		const calls = makeCalls();
		const ctx = makeCtx(cwd, calls);
		ctx.hasUI = false;
		ctx.ui.confirm = async () => true;
		const execCalls: Array<{ command: string; args: string[] }> = [];
		const pi = {
			...makePi(),
			async exec(command: string, args: string[]) {
				execCalls.push({ command, args });
				return { stdout: JSON.stringify({ preset: "gemini-inspired", theme: "fried-apple-pie-gemini" }), stderr: "", code: 0, killed: false };
			},
		};
		await importConfig("https://example.test/pie-ui.json", ctx, pi as any, { working: false });
		assert.deepEqual(execCalls, [{ command: "curl", args: ["-fsSL", "https://example.test/pie-ui.json"] }]);
		const written = JSON.parse(readFileSync(join(cwd, ".pi", "pie-ui.json"), "utf8"));
		assert.equal(written.preset, "gemini-inspired");
		assert.equal(calls.themes.at(-1), "fried-apple-pie-gemini");
	});
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

test("recordHistory writes JSON history and appends session entry", () => {
	withTempHome(() => {
		const appended: Array<{ customType: string; data: unknown }> = [];
		const entry = { ts: 1, scope: "global" as const, path: "/tmp/x", previous: { preset: "minimal" as const }, next: { preset: "codex-inspired" as const } };
		recordHistory({ appendEntry: (customType: string, data: unknown) => appended.push({ customType, data }) } as any, entry);
		assert.deepEqual(readHistory(), [entry]);
		assert.deepEqual(appended, [{ customType: PIE_HISTORY_TYPE, data: entry }]);
	});
});

test("postStats is opt-in and sends anonymized payload", async () => {
	const disabledCalls: unknown[] = [];
	const disabled = await postStats({ preset: "minimal" }, async (...args: unknown[]) => {
		disabledCalls.push(args);
		return { ok: true, status: 204 };
	});
	assert.deepEqual(disabled, { sent: false, reason: "disabled" });
	assert.deepEqual(disabledCalls, []);

	const config = { preset: "codex-inspired" as const, persona: "arc", layers: ["theme:gemini"], analytics: { enabled: true, endpoint: "https://stats.example.test" } };
	const calls: Array<{ url: string; body: string }> = [];
	const sent = await postStats(config, async (url, init) => {
		calls.push({ url, body: init.body });
		return { ok: true, status: 204 };
	}, "/home/test", "machine");
	assert.deepEqual(sent, { sent: true, status: 204 });
	assert.equal(calls[0].url, "https://stats.example.test");
	const payload = JSON.parse(calls[0].body);
	assert.equal(payload.preset, "codex-inspired");
	assert.equal(payload.persona, "arc");
	assert.deepEqual(payload.layers, ["theme:gemini"]);
	assert.equal(typeof payload.hashedInstallId, "string");
	assert.equal(payload.hashedInstallId, hashedInstallId("/home/test", "machine"));
	assert.equal(statsPayload(config, "/home/test", "machine").hashedInstallId, hashedInstallId("/home/test", "machine"));
	assert.equal(analyticsStatus(config), "analytics: enabled -> https://stats.example.test");
	assert.equal(analyticsStatus({ preset: "minimal" }), "analytics: disabled");
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
	assert.equal(pkg.exports["./sdk"].types, "./extensions/pie-ui/sdk.ts");
	assert.equal(pkg.bin.fap, "./bin/fap.mjs");
	assert.ok(pkg.files.includes("bin"));
	assert.ok(pkg.files.includes("examples"));
	assert.deepEqual(pkg.pi.skills, ["./skills"]);
	assert.deepEqual(pkg.pi.themes, ["./themes"]);
	assert.match(pkg.pi.image, /^https:\/\/raw\.githubusercontent\.com\//);
	const png = readFileSync("assets/fried-apple-pie-gallery.png");
	assert.equal(png.readUInt32BE(16), 1200);
	assert.equal(png.readUInt32BE(20), 740);
});

test("packaged skill has Pi-required frontmatter", () => {
	const skill = readFileSync("skills/fried-apple-pie/SKILL.md", "utf8");
	assert.match(skill, /^---\n/);
	assert.match(skill, /\nname: fried-apple-pie\n/);
	assert.match(skill, /\ndescription: .+\n/);
});

test("fap capture-terminal writes a valid theme from ANSI JSON", () => {
	const dir = mkdtempSync(join(tmpdir(), "fap-cli-"));
	const out = join(dir, "unit-theme.json");
	const ansi = Object.fromEntries(Array.from({ length: 16 }, (_value, index) => [String(index), `#${index.toString(16).repeat(6)}`]));
	const result = spawnSync(process.execPath, ["bin/fap.mjs", "capture-terminal", "--name", "unit-terminal", "--out", out, "--ansi-json", JSON.stringify(ansi)], { encoding: "utf8" });
	assert.equal(result.status, 0, result.stderr);
	const theme = JSON.parse(readFileSync(out, "utf8")) as { name?: string; colors?: Record<string, string> };
	assert.equal(theme.name, "unit-terminal");
	assert.equal(theme.colors?.error, "#111111");
	assert.equal(theme.colors?.accent, "#555555");
	for (const token of requiredThemeTokens) assert.ok(theme.colors && token in theme.colors, token);
});

test("preset SDK defines third-party preset specs", () => {
	const spec = defineFriedApplePiePreset({
		name: "demo",
		theme: { name: "fried-apple-pie-demo", colors: { accent: "#fff" } },
		config: { preset: "minimal", theme: "fried-apple-pie-demo" },
	});
	assert.equal(spec.name, "demo");
	assert.throws(() => defineFriedApplePiePreset({ ...spec, name: "" }), /preset name/);
	assert.equal(existsSync("examples/third-party-preset/index.ts"), true);
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
