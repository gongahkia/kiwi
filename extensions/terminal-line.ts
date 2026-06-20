/**
 * Fried Apple Pie terminal line
 *
 * A Claude-style pi footer inspired by the screenshot:
 * model▸thinking · cwd · git-branch-if-present · Working/Ready · Context N% left
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

const COLORS = {
	model: "#f4e5a1",
	path: "#afe7ad",
	branch: "#9dbdff",
	status: "#c9a7ff",
	context: "#ffc18f",
	separator: "#81898f",
};

function hex(color: string, text: string): string {
	const value = color.replace("#", "");
	const r = parseInt(value.slice(0, 2), 16);
	const g = parseInt(value.slice(2, 4), 16);
	const b = parseInt(value.slice(4, 6), 16);
	return `\x1b[38;2;${r};${g};${b}m${text}\x1b[39m`;
}

function sep(): string {
	return hex(COLORS.separator, " · ");
}

function compactCwd(cwd: string): string {
	const home = process.env.HOME;
	return home && cwd.startsWith(home) ? `~${cwd.slice(home.length)}` : cwd;
}

function contextLeft(ctx: ExtensionContext): string {
	const usage = ctx.getContextUsage();
	if (!usage || usage.percent === null) return "Context -- left";
	const left = Math.max(0, Math.min(100, Math.round(100 - usage.percent)));
	return `Context ${left}% left`;
}

export default function (pi: ExtensionAPI) {
	let working = false;
	let render: (() => void) | undefined;

	function requestRender() {
		render?.();
	}

	function install(ctx: ExtensionContext) {
		if (ctx.mode !== "tui") return;

		ctx.ui.setFooter((tui, _theme, footerData) => {
			render = () => tui.requestRender();
			const unsub = footerData.onBranchChange(() => tui.requestRender());

			return {
				dispose() {
					unsub();
					render = undefined;
				},
				invalidate() {},
				render(width: number): string[] {
					const model = ctx.model?.id ?? "no-model";
					const thinking = pi.getThinkingLevel();
					const branch = footerData.getGitBranch();
					const status = working ? "Working" : "Ready";

					const parts = [
						hex(COLORS.model, `${model}▸${thinking}`),
						hex(COLORS.path, compactCwd(ctx.cwd)),
						...(branch ? [hex(COLORS.branch, branch)] : []),
						hex(COLORS.status, status),
						hex(COLORS.context, contextLeft(ctx)),
					];

					const line = parts.join(sep());
					const leftPad = visibleWidth(line) < width ? " " : "";
					return [truncateToWidth(leftPad + line, width)];
				},
			};
		});
	}

	pi.on("session_start", (_event, ctx) => install(ctx));
	pi.on("agent_start", () => {
		working = true;
		requestRender();
	});
	pi.on("agent_end", () => {
		working = false;
		requestRender();
	});
	pi.on("model_select", () => requestRender());
	pi.on("thinking_level_select", () => requestRender());
	pi.on("message_end", () => requestRender());

	pi.registerCommand("terminal-line", {
		description: "Reinstall the Fried Apple Pie terminal line",
		handler: async (_args, ctx) => {
			install(ctx);
			ctx.ui.notify("Fried Apple Pie terminal line reloaded", "info");
		},
	});
}
