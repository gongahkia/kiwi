import type { AutocompleteProvider, AutocompleteSuggestions } from "@earendil-works/pi-tui";
import { FOOTER_SEGMENTS, MODE_NAMES, PRESET_NAMES, PRESET_THEMES, TOOL_RENDER_STYLES, WHEN_RULES } from "./config.ts";
import { PERSONA_NAMES } from "./personas.ts";

const CONFIG_KEYS = [
	"$schema",
	"preset",
	"theme",
	"mode",
	"compact",
	"strict",
	"persona",
	"layers",
	"header",
	"enabled",
	"title",
	"subtitle",
	"footer",
	"segments",
	"separator",
	"widget",
	"placement",
	"lines",
	"welcome",
	"banner",
	"tools",
	"expanded",
	"renderStyle",
	"thinking",
	"hiddenLabel",
	"working",
	"visible",
	"message",
	"frames",
	"intervalMs",
	"notifications",
	"contextWarnings",
	"id",
	"when",
] as const;

const VALUE_ENUMS: Record<string, readonly string[]> = {
	preset: PRESET_NAMES,
	theme: Object.values(PRESET_THEMES),
	mode: MODE_NAMES,
	persona: PERSONA_NAMES,
	renderStyle: TOOL_RENDER_STYLES,
	segments: FOOTER_SEGMENTS,
	id: FOOTER_SEGMENTS,
	when: WHEN_RULES,
	placement: ["aboveEditor", "belowEditor"],
};

export function createPieAutocompleteProvider(current: AutocompleteProvider): AutocompleteProvider {
	return {
		triggerCharacters: ['"', ":"],
		async getSuggestions(lines, cursorLine, cursorCol, options) {
			return pieAutocompleteSuggestions(lines, cursorLine, cursorCol) ?? current.getSuggestions(lines, cursorLine, cursorCol, options);
		},
		applyCompletion(lines, cursorLine, cursorCol, item, prefix) {
			return current.applyCompletion(lines, cursorLine, cursorCol, item, prefix);
		},
		shouldTriggerFileCompletion(lines, cursorLine, cursorCol) {
			return current.shouldTriggerFileCompletion?.(lines, cursorLine, cursorCol) ?? true;
		},
	};
}

export function pieAutocompleteSuggestions(lines: string[], cursorLine: number, cursorCol: number): AutocompleteSuggestions | null {
	if (!looksLikePieConfig(lines)) return null;
	const line = lines[cursorLine] ?? "";
	const before = line.slice(0, cursorCol);
	const valueMatch = before.match(/"([^"]+)"\s*:\s*"([^"]*)$/);
	if (valueMatch) {
		const [, key, typed] = valueMatch;
		return enumSuggestions(key, typed);
	}
	const arrayKey = arrayContext(lines, cursorLine);
	const arrayMatch = before.match(/"([^"]*)$/);
	if (arrayMatch && arrayKey) return enumSuggestions(arrayKey, arrayMatch[1]);
	const keyMatch = before.match(/(?:^|[,{]\s*)\s*"([^"]*)$/);
	if (keyMatch) {
		const typed = keyMatch[1];
		return quotedSuggestions(CONFIG_KEYS, typed, "config key");
	}
	return null;
}

function enumSuggestions(key: string, typed = ""): AutocompleteSuggestions | null {
	const values = VALUE_ENUMS[key];
	return values ? quotedSuggestions(values, typed, key) : null;
}

function quotedSuggestions(values: readonly string[], typed: string, description: string): AutocompleteSuggestions {
	return {
		prefix: `"${typed}`,
		items: values
			.filter((value) => value.startsWith(typed))
			.map((value) => ({
				label: value,
				value: `"${value}"`,
				description,
			})),
	};
}

function looksLikePieConfig(lines: string[]): boolean {
	const text = lines.join("\n");
	return /^\s*\{/.test(text) && /"(preset|footer|tools|mode|theme|persona)"/.test(text);
}

function arrayContext(lines: string[], cursorLine: number): string | undefined {
	for (let i = cursorLine; i >= 0; i--) {
		const line = lines[i] ?? "";
		const start = line.match(/"([^"]+)"\s*:\s*\[/);
		if (start) return start[1];
		if (line.includes("]")) return undefined;
	}
	return undefined;
}
