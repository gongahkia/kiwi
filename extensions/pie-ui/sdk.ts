import type { PieConfig } from "./config.ts";

export type ThemeFile = {
	$schema?: string;
	name: string;
	vars?: Record<string, string>;
	colors: Record<string, string>;
};

export type PresetDefinition = {
	name: string;
	theme: ThemeFile;
	config: Partial<PieConfig>;
	banner?: string[];
	persona?: {
		spinner: string;
		verbs: string[];
		systemPromptSuffix?: string;
	};
};

export type FriedApplePiePresetModule = {
	default: PresetDefinition;
	__friedApplePiePreset?: true;
};

export const FRIED_APPLE_PIE_PRESET_MARKER = "__friedApplePiePreset";

export function defineFriedApplePiePreset<T extends PresetDefinition>(spec: T): T {
	if (!spec.name.trim()) throw new Error("preset name is required");
	if (!spec.theme?.name?.trim()) throw new Error("theme.name is required");
	if (!spec.theme.colors || typeof spec.theme.colors !== "object") throw new Error("theme.colors is required");
	if (!spec.config || typeof spec.config !== "object") throw new Error("config is required");
	return spec;
}
