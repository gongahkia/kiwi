import type { PresetName } from "./config.ts";

// spinner frame sets, vendored subset of sindresorhus/cli-spinners (MIT).
// source: https://github.com/sindresorhus/cli-spinners/blob/main/spinners.json
export type SpinnerSpec = { frames: string[]; intervalMs: number };

export const SPINNERS: Record<string, SpinnerSpec> = {
	dots: { frames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"], intervalMs: 80 },
	dots2: { frames: ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"], intervalMs: 80 },
	dots3: { frames: ["⠋", "⠙", "⠚", "⠞", "⠖", "⠦", "⠴", "⠲", "⠳", "⠓"], intervalMs: 80 },
	arc: { frames: ["◜", "◠", "◝", "◞", "◡", "◟"], intervalMs: 100 },
	line: { frames: ["-", "\\", "|", "/"], intervalMs: 130 },
	arrow: { frames: ["←", "↖", "↑", "↗", "→", "↘", "↓", "↙"], intervalMs: 100 },
	moon: { frames: ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"], intervalMs: 80 },
	earth: { frames: ["🌍", "🌎", "🌏"], intervalMs: 180 },
	triangle: { frames: ["◢", "◣", "◤", "◥"], intervalMs: 50 },
	aesthetic: { frames: ["▰▱▱▱▱▱▱", "▰▰▱▱▱▱▱", "▰▰▰▱▱▱▱", "▰▰▰▰▱▱▱", "▰▰▰▰▰▱▱", "▰▰▰▰▰▰▱", "▰▰▰▰▰▰▰"], intervalMs: 80 },
};

// each persona pairs a spinner with a verb pack. verbs are rotated through on each turn.
export type PersonaSpec = {
	spinner: keyof typeof SPINNERS;
	verbs: string[];
	systemPromptSuffix?: string; // p1-15 hook, unused in v1
};

export const PERSONAS: Record<string, PersonaSpec> = {
	default: { spinner: "dots", verbs: ["Working", "Thinking", "Processing"] },
	terse: { spinner: "line", verbs: ["Working"] },
	arc: { spinner: "arc", verbs: ["Working", "Reasoning"] },
	startrek: { spinner: "dots3", verbs: ["Engaging warp drive", "Running diagnostics", "Hailing frequencies"] },
	medieval: { spinner: "triangle", verbs: ["Forging", "Conjuring", "Questing"] },
	pirate: { spinner: "moon", verbs: ["Plunderin'", "Hoistin' sails", "Searchin' the seas"] },
	mlengineer: { spinner: "aesthetic", verbs: ["Tuning", "Training", "Evaluating"] },
};

export const PERSONA_NAMES = Object.keys(PERSONAS) as readonly string[];

// default persona per preset. user can override via config.persona.
export const PRESET_DEFAULT_PERSONA: Record<PresetName, string> = {
	minimal: "terse",
	"claude-inspired": "default",
	"opencode-inspired": "default",
	"codex-inspired": "arc",
	"gemini-inspired": "default",
	"aider-inspired": "terse",
	"copilot-inspired": "default",
	dracula: "default",
	"tokyo-night": "default",
	"catppuccin-mocha": "default",
	nord: "default",
	"gruvbox-dark": "default",
};

export function resolvePersona(personaName: string | undefined, preset: PresetName | undefined): PersonaSpec | undefined {
	if (personaName && PERSONAS[personaName]) return PERSONAS[personaName];
	if (preset && PRESET_DEFAULT_PERSONA[preset]) return PERSONAS[PRESET_DEFAULT_PERSONA[preset]];
	return PERSONAS.default;
}
