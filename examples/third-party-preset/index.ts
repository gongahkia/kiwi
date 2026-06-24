import { defineFriedApplePiePreset } from "fried-apple-pie/sdk";

export default defineFriedApplePiePreset({
	name: "example-terminal",
	theme: {
		name: "fried-apple-pie-example-terminal",
		colors: {
			accent: "#7c3aed",
			text: "#f8fafc",
			muted: "#94a3b8",
			toolPendingBg: "#111827",
			toolSuccessBg: "#052e16",
			toolErrorBg: "#450a0a",
		},
	},
	config: {
		preset: "minimal",
		theme: "fried-apple-pie-example-terminal",
		footer: { enabled: true, segments: ["model", "branch", "status", "context"] },
		tools: { expanded: false, renderStyle: "pill" },
	},
	banner: ["fried apple pie example preset"],
	persona: {
		spinner: "dots",
		verbs: ["Working", "Polishing"],
	},
});
