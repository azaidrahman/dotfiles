// dot_omp/agent/extensions/lesson-log.ts
// Mirror a teach lesson to the Obsidian note named in ~/.config/lesson-log.
// Same note format as the Claude Code hook (dot_claude/hooks/lesson-log.sh).
//
//   message_end (user)          -> YOU
//   message_end (assistant)     -> TUTOR (text blocks only)
//   tool_call ask               -> one Question per entry in `questions`
//   tool_execution_update quiz  -> Question in the shuffled display order
//   tool_result ask             -> YOU, one line per question
//   tool_result quiz            -> YOU (choice) then TUTOR (grade + explanation)
//
// Only the session that first sees the link file may write. It records
// "omp:<sessionId>" in ~/.config/lesson-log.session; the Claude hook reads the
// same file and exits when the id is not its own transcript path.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
	askAnswerLines,
	questionBlock,
	quizGradeBlock,
	stripSkillBlocks,
	tutorBlock,
	youBlock,
} from "../lib/lesson-format";

const LINK = path.join(os.homedir(), ".config", "lesson-log");
const OWNER = path.join(os.homedir(), ".config", "lesson-log.session");

export default function (pi: ExtensionAPI) {
	let sessionId = "";
	let warned = false;

	const skip = (ctx: { hasUI?: boolean }) => ctx.hasUI === false;

	// Resolve the note this session may write to, or null.
	function noteFor(): string | null {
		let note: string;
		try {
			note = fs.readFileSync(LINK, "utf-8").trim();
		} catch {
			return null;
		}
		if (!note || !fs.existsSync(note)) return null;
		if (!sessionId) return null;
		const me = `omp:${sessionId}`;
		try {
			const owner = fs.readFileSync(OWNER, "utf-8").split("\n")[0];
			// An empty first line means a crashed writer left a zero-byte file.
			// Do not let that lock the note forever; claim it instead.
			if (owner !== "" && owner !== me) return null;
			if (owner === "") fs.writeFileSync(OWNER, `${me}\n`, "utf-8");
		} catch {
			try {
				fs.writeFileSync(OWNER, `${me}\n`, "utf-8");
			} catch {
				return null;
			}
		}
		return note;
	}

	// Appends can fire close together; keep them ordered. A rejection must
	// never propagate, or every later append would be silently skipped.
	let chain: Promise<void> = Promise.resolve();
	function append(block: string, ctx: { ui?: { notify?: (m: string, t: string) => void } }): Promise<void> {
		chain = chain
			.then(() => {
				const note = noteFor();
				if (!note) return;
				try {
					const current = fs.readFileSync(note, "utf-8");
					const base = current.replace(/\n+$/, "");
					fs.writeFileSync(note, `${base}${base ? "\n\n" : ""}${block}\n`, "utf-8");
				} catch (e) {
					if (!warned) {
						warned = true;
						try {
							ctx.ui?.notify?.(`lesson-log: cannot write ${note}: ${String(e)}`, "warning");
						} catch {
							// Never let a broken notify sink poison the chain.
						}
					}
				}
			})
			.catch(() => {});
		return chain;
	}

	const textOf = (content: unknown): string => {
		if (typeof content === "string") return content;
		if (!Array.isArray(content)) return "";
		return content
			.filter((c: { type?: string }) => c?.type === "text")
			.map((c: { text?: string }) => (c.text ?? "").trim())
			.filter((t: string) => t.length > 0)
			.join("\n\n");
	};

	pi.on("session_start", (_event, ctx) => {
		try {
			sessionId = ctx.sessionManager?.getSessionId?.() ?? "";
		} catch {
			sessionId = "";
		}
	});

	pi.on("message_end", async (event, ctx) => {
		if (skip(ctx)) return;
		const msg = event.message as { role?: string; content?: unknown };
		if (msg?.role === "user") {
			const text = stripSkillBlocks(textOf(msg.content).trim());
			if (text) await append(youBlock(text), ctx);
		} else if (msg?.role === "assistant") {
			const text = textOf(msg.content);
			if (text) await append(tutorBlock(text), ctx);
		}
	});

	// `ask` shows options in the order given, so the call is the display order.
	pi.on("tool_call", async (event, ctx) => {
		if (skip(ctx)) return;
		const e = event as { toolName?: string; input?: { questions?: Array<{ question?: string; options?: Array<{ label?: string } | string> }> } };
		if (e.toolName !== "ask") return;
		for (const q of e.input?.questions ?? []) {
			const labels = (q.options ?? []).map((o) => (typeof o === "string" ? o : o.label ?? ""));
			await append(questionBlock(q.question ?? "", labels), ctx);
		}
	});

	// `quiz` shuffles inside execute(), so wait for its first update, which
	// carries the true display order. One write per call id.
	const loggedQuiz = new Set<string>();
	pi.on("tool_execution_update", async (event, ctx) => {
		if (skip(ctx)) return;
		const e = event as { toolName?: string; toolCallId: string; args?: { question?: string }; partialResult?: { details?: { options?: Array<{ label: string }> } } };
		if (e.toolName !== "quiz" || loggedQuiz.has(e.toolCallId)) return;
		const opts = e.partialResult?.details?.options;
		if (!opts?.length) return;
		loggedQuiz.add(e.toolCallId);
		await append(questionBlock(e.args?.question ?? "", opts.map((o) => o.label)), ctx);
	});

	pi.on("tool_result", async (event, ctx) => {
		if (skip(ctx)) return;
		const e = event as {
			toolName?: string;
			content?: unknown;
			details?: {
				status?: string;
				correct?: boolean;
				dontKnow?: boolean;
				correctIndices?: number[];
				options?: Array<{ label: string }>;
				answers?: Array<{ label: string }>;
				explanation?: string;
			};
		};
		if (e.toolName === "ask") {
			await append(youBlock(askAnswerLines(textOf(e.content)).join("\n")), ctx);
			return;
		}
		if (e.toolName !== "quiz") return;
		const d = e.details ?? {};
		if (d.status === "cancelled" || d.status === "unavailable") {
			await append(youBlock("(no answer)"), ctx);
			return;
		}
		const chosen = d.dontKnow ? "I don't know" : (d.answers ?? []).map((a) => a.label).join(", ") || "(no answer)";
		await append(youBlock(chosen), ctx);
		const correctLabels = (d.correctIndices ?? []).map((i) => d.options?.[i - 1]?.label ?? String(i));
		await append(
			quizGradeBlock({ correct: d.correct === true, dontKnow: d.dontKnow === true, correctLabels, explanation: d.explanation ?? "" }),
			ctx,
		);
	});
}
