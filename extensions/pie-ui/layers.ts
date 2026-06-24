import type { PieConfig } from "./config.ts";

// composable partial-config overlays applied between preset and user config.
// users mix layers via `layers: ["theme:codex", "footer:powerline"]`.
export const LAYERS: Record<string, Partial<PieConfig>> = {
	"theme:claude": { theme: "fried-apple-pie-claude" },
	"theme:codex": { theme: "fried-apple-pie-codex" },
	"theme:gemini": { theme: "fried-apple-pie-gemini" },
	"theme:opencode": { theme: "fried-apple-pie-opencode" },
	"theme:dracula": { theme: "fried-apple-pie-dracula" },
	"theme:nord": { theme: "fried-apple-pie-nord" },
	"theme:tokyo-night": { theme: "fried-apple-pie-tokyo-night" },
	"theme:catppuccin-mocha": { theme: "fried-apple-pie-catppuccin-mocha" },
	"theme:gruvbox-dark": { theme: "fried-apple-pie-gruvbox-dark" },

	"footer:minimal": { footer: { enabled: true, segments: ["model", "cwd", "status"], separator: " " } },
	"footer:dense": { footer: { enabled: true, segments: ["model", "thinking", "cwd", "branch", "status", "context", "tokens"], separator: " · " } },
	"footer:powerline": { footer: { enabled: true, segments: ["model", "cwd", "branch", "status", "context"], separator: "  " } },
	"footer:none": { footer: { enabled: false } },

	"welcome:on": { widget: { enabled: true, placement: "aboveEditor", lines: ["Fried Apple Pie · /pie welcome for info"] } },
	"welcome:none": { widget: { enabled: false }, header: { enabled: false } },

	"persona:default": { persona: "default" },
	"persona:terse": { persona: "terse" },
	"persona:arc": { persona: "arc" },
	"persona:startrek": { persona: "startrek" },
	"persona:medieval": { persona: "medieval" },
	"persona:pirate": { persona: "pirate" },
	"persona:mlengineer": { persona: "mlengineer" },

	"compact:on": { compact: true },
	"compact:off": { compact: false },
};

export const LAYER_NAMES = Object.keys(LAYERS).sort();
