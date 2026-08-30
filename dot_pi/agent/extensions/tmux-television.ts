// Name the tmux window after the first prompt of a pi session, and report the
// project-trust prompt to the shared notify hook.
//
// Window state, banners, pushes, and the tmux alert log all live in
// ~/.claude/hooks/notify-tmux.sh, driven by notify-tmux.ts. This file only
// keeps what that hook cannot do for pi: the hook auto-names a window from the
// pane title that Claude Code sets, and pi sets no such title, so the name
// comes from the prompt here instead.
import { execSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { fireNotify } from "../lib/notify-hook";

export default function (pi: ExtensionAPI) {
	const pane = process.env.TMUX_PANE;
	if (!pane) return;

	const tq = (cmd: string) => {
		try {
			return execSync(cmd, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
		} catch {
			return "";
		}
	};

	let winId = "";
	let wname = "pi";
	const parts = tq(`tmux display-message -p -t "${pane}" '#{window_id}\t#{window_name}'`).split("\t");
	if (parts.length === 2) [winId, wname] = parts;
	if (!winId) return;

	const isDefaultName = (name: string) => /^(|zsh|-zsh|bash|-bash|sh|fish|node|claude|pi|login)$/.test(name);

	const kebabShort = (text: string, maxWords: number) =>
		text
			.toLowerCase()
			.replace(/[^a-z0-9 -]/g, "")
			.replace(/\s+/g, " ")
			.trim()
			.split(" ")
			.slice(0, maxWords)
			.join("-");

	const autonameDone = () => Boolean(tq(`tmux show-options -wqv -t "${winId}" @claude_autoname_done`));

	const autonameCapture = (prompt: string, cwd: string) => {
		if (autonameDone()) return;

		let ticket = "";
		const branch = tq(`git -C "${cwd}" rev-parse --abbrev-ref HEAD`);
		const match = branch.match(/[A-Z]+-[0-9]+/);
		if (match) ticket = match[0];

		// The first line of the prompt is the topic.
		const topic = prompt.split("\n")[0].trim();
		if (!topic || !topic.includes(" ") || isDefaultName(topic)) return;

		const max = ticket ? 3 : 4;
		const name = ticket ? `${ticket} ${kebabShort(topic, max)}` : kebabShort(topic, max);

		tq(`tmux set-option -w -t "${winId}" @claude_autoname_done 1`);
		tq(`tmux set-option -w -t "${winId}" @claude_base "${name}"`);
	};

	pi.on("before_agent_start", async (event, ctx) => {
		if (ctx.hasUI === false) return;
		// A window that already carries a custom name was named by the user. Keep it.
		const stripped = wname.replace(/^[^a-zA-Z0-9]+\s*/, "").trim();
		if (!isDefaultName(stripped) && !autonameDone()) {
			tq(`tmux set-option -w -t "${winId}" @claude_autoname_done 1`);
		}
		autonameCapture(event.prompt, ctx.cwd);
	});

	pi.on("project_trust", async () => {
		fireNotify("permission_prompt", { message: "pi asks whether to trust this project" });
		return { trusted: "undecided" }; // the built-in flow decides
	});
}
