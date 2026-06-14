import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import * as path from "node:path";

const PALETTE = [82, 226, 208, 196]; // green, yellow, orange, red
const GRAY = 244;

function rankColor(value: string, ranks: string[]): string {
	const lc = value.toLowerCase();
	for (let i = 0; i < ranks.length; i++) {
		const pats = ranks[i].split('|');
		for (const pat of pats) {
			const cleanPat = pat.replace(/\*/g, '');
			if (cleanPat && lc.includes(cleanPat)) {
				const color = PALETTE[Math.floor((i * PALETTE.length) / ranks.length)];
				return `\x1b[38;5;${color}m`;
			}
		}
	}
	return `\x1b[38;5;${GRAY}m`;
}

const MODEL_RANK = ['haiku', 'sonnet', 'opus', 'fable', 'gpt'];
const EFFORT_RANK = ['low|minimal', 'medium|normal', 'high', 'xhigh', 'ultra|max|highest'];

function colorForCost(usd: number): string {
	if (usd < 20) return '\x1b[38;5;244m';
	if (usd < 50) return '\x1b[38;5;82m';
	if (usd < 75) return '\x1b[38;5;226m';
	if (usd < 100) return '\x1b[38;5;208m';
	return '\x1b[38;5;196m';
}

function colorForRate(pct: number): string {
	if (pct < 50) return '\x1b[38;5;244m';
	if (pct < 70) return '\x1b[38;5;82m';
	if (pct < 85) return '\x1b[38;5;226m';
	if (pct < 95) return '\x1b[38;5;208m';
	return '\x1b[38;5;196m';
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		// Ensure this only sets up UI stuff if there's a UI
		if (!ctx.hasUI) return;

		ctx.ui.setFooter((tui, theme, footerData) => {
			const unsubBranch = footerData.onBranchChange(() => tui.requestRender());
			const unsubExt = footerData.onExtensionStatusChange(() => tui.requestRender());

			return {
				dispose() {
					unsubBranch();
					unsubExt();
				},
				invalidate() {},
				render(width: number): string[] {
					// Gather stats
					let input = 0;
					let output = 0;
					let cost = 0;
					for (const e of ctx.sessionManager.getBranch()) {
						if (e.type === "message" && e.message.role === "assistant") {
							const m = e.message as AssistantMessage;
							input += m.usage?.input || 0;
							output += m.usage?.output || 0;
							cost += m.usage?.cost?.total || 0;
						}
					}

					const model = ctx.model?.id || "no-model";
					const effort = pi.getThinkingLevel();
					
					const ctxWindow = ctx.model?.contextWindow || 200000;
					const ctxPct = Math.min(100, Math.round(((input + output) / ctxWindow) * 100));

					const wt = path.basename(ctx.cwd);
					const br = footerData.getGitBranch() || "";

					const segments: string[] = [];
					const reset = "\x1b[38;5;244m"; // our base dim gray
					
					// model
					segments.push(`${rankColor(model, MODEL_RANK)}${model}${reset}`);
					
					// effort
					if (effort !== "off") {
						segments.push(`${rankColor(effort, EFFORT_RANK)}eff:${effort}${reset}`);
					}
					
					// cost
					segments.push(`${colorForCost(cost)}$${cost.toFixed(2)}${reset}`);
					
					// ctx
					segments.push(`ctx:${ctxPct}%`);
					
					// wt
					if (wt) segments.push(`wt:${wt}`);
					
					// br
					if (br) segments.push(`br:${br}`);

					// Extension statuses (for things like plan mode)
					const extStatuses = Array.from(footerData.getExtensionStatuses().values());
					for (const s of extStatuses) {
						if (s) segments.push(s);
					}

					const sep = "  |  ";
					const lineContent = segments.join(sep);
					
					// Wrap in our base dim color and add the reset at the very end
					// so that any internal color changes fall back to our gray for the separators
					const finalLine = `\x1b[38;5;244m${lineContent}\x1b[0m`;
					
					return [truncateToWidth(finalLine, width)];
				},
			};
		});
	});
}
