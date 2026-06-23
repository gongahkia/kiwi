import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { applyJsonPatch, effectiveConfig, PRESET_NAMES, PRESET_THEMES, validateConfig } from "../extensions/pie-ui/config.ts";

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
