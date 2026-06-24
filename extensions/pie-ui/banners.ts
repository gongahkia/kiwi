import type { PieConfig, PresetName } from "./config.ts";

export const BANNERS: Record<PresetName, string[]> = {
	minimal: [
		"+----------------------+",
		"| fried apple pie      |",
		"| minimal / quiet ui   |",
		"+----------------------+",
	],
	"claude-inspired": [
		"      .------------.",
		"  .---| warm prompt |---.",
		"  `---| pie / claude |---'",
		"      `------------'",
	],
	"opencode-inspired": [
		"  [ cwd ]--[ git ]--[ model ]",
		"       fried apple pie",
		"  [ open code inspired rails ]",
	],
	"codex-inspired": [
		"  +== fried apple pie ==+",
		"  || dense reasoning ui ||",
		"  +== codex inspired ===+",
	],
	"gemini-inspired": [
		"     /\\   fried apple pie",
		"    /  \\  bright twin rails",
		"   /____\\ gemini inspired",
	],
	"aider-inspired": [
		"  pie> edit",
		"  pie> diff",
		"  pie> aider-inspired",
	],
	"copilot-inspired": [
		"  < fried apple pie />",
		"  { model | branch | ctx }",
		"  < copilot-inspired />",
	],
	"cursor-inspired": [
		"  | cursor line |",
		"  | fried pie   |",
		"  | blue signal |",
	],
	"amp-inspired": [
		"  .-- amp rail --.",
		"  | fried pie    |",
		"  `-- warm glow --'",
	],
	dracula: [
		"  .---- night crust ----.",
		"  | fried apple pie     |",
		"  `---- dracula --------'",
	],
	"tokyo-night": [
		"  === tokyo night ===",
		"      fried pie",
		"  === neon footer ===",
	],
	"catppuccin-mocha": [
		"  ( mocha shell )",
		"  ( fried pie   )",
		"  ( pastel tui  )",
	],
	"catppuccin-latte": [
		"  [ latte shell ]",
		"  [ fried pie   ]",
		"  [ soft tui    ]",
	],
	nord: [
		"  / frost / branch /",
		" / fried apple pie /",
		"/ nord interface  /",
	],
	"gruvbox-dark": [
		"  +-- warm dark --+",
		"  | fried pie     |",
		"  +-- gruvbox ----+",
	],
	"gruvbox-light": [
		"  +-- warm light -+",
		"  | fried pie     |",
		"  +-- gruvbox ----+",
	],
};

export function bannerForConfig(config: PieConfig): string[] {
	const custom = config.welcome?.banner;
	if (custom?.length) return [...custom];
	return [...BANNERS[config.preset ?? "minimal"]];
}
