import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import * as path from "node:path";

// pi-tui ships under different scopes depending on the installed pi build
// (newer @earendil-works/*, older Homebrew @mariozechner/*). Resolve through
// pi's own module loader against whichever is present, and degrade gracefully
// if neither resolves so a missing module never kills the whole extension.
let truncateToWidth: (line: string, width: number) => string = (line, width) =>
	line.slice(0, Math.max(0, width));
for (const scope of ["@earendil-works/pi-tui", "@mariozechner/pi-tui"]) {
	try {
		({ truncateToWidth } = await import(scope));
		break;
	} catch {
		// try the next scope
	}
}

const PALETTE = [82, 226, 208, 196]; // green, yellow, orange, red
const GRAY = 244;
const RESET = "\x1b[0m";

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

const MODEL_RANK = ['haiku', 'sonnet', 'opus', 'fable', 'gemini', 'gpt-5'];
const EFFORT_RANK = ['low|minimal', 'medium|normal', 'high', 'xhigh', 'ultra|max|highest'];

function colorForCost(usd: number): string {
	if (usd < 20) return '\x1b[38;5;244m';
	if (usd < 50) return '\x1b[38;5;82m';
	if (usd < 75) return '\x1b[38;5;226m';
	if (usd < 100) return '\x1b[38;5;208m';
	return '\x1b[38;5;196m';
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		if (ctx.mode !== "tui") return;

		ctx.ui.setFooter((tui, _theme, footerData) => {
			const unsubBranch = footerData.onBranchChange(() => tui.requestRender());
			const unsubExt = footerData.onExtensionStatusChange(() => tui.requestRender());

			return {
				dispose() {
					unsubBranch();
					unsubExt();
				},
				invalidate() {},
				render(width: number): string[] {
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

					const modelName = ctx.model?.name || ctx.model?.id || "no-model";
					let model = modelName;
					if (model.includes("claude-")) model = model.replace("claude-", "");
					if (model.includes("gemini-")) model = model.replace("gemini-", "gem-");

					const effort = pi.getThinkingLevel();
					const ctxWindow = ctx.model?.contextWindow || 200000;
					const ctxPct = Math.min(100, Math.round(((input + output) / ctxWindow) * 100));
					const wt = path.basename(ctx.cwd);
					const br = footerData.getGitBranch() || "";

					const segments: string[] = [];
					
					// mode color
					segments.push(`\x1b[38;5;75mINSERT\x1b[0m`);

					// model
					segments.push(`${rankColor(modelName, MODEL_RANK)}${model}${RESET}`);
					
					// effort
					if (effort !== "off") {
						segments.push(`${rankColor(effort, EFFORT_RANK)}eff:${effort}${RESET}`);
					}
					
					// cost
					segments.push(`${colorForCost(cost)}$${cost.toFixed(2)}${RESET}`);
					
					// ctx
					segments.push(`\x1b[38;5;244mctx:${ctxPct}%\x1b[0m`);
					
					// wt
					if (wt) segments.push(`\x1b[38;5;244mwt:${wt}\x1b[0m`);
					
					// br
					if (br) segments.push(`\x1b[38;5;244mbr:${br}\x1b[0m`);

					// Extension statuses
					for (const s of Array.from(footerData.getExtensionStatuses().values())) {
						if (s) segments.push(`\x1b[38;5;244m${s}\x1b[0m`);
					}

					const sep = `\x1b[38;5;244m  |  \x1b[0m`;
					const line = segments.join(sep);
					return [truncateToWidth(line, width)];
				},
			};
		});
	});
}
