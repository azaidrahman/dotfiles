import { execSync, spawn } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as path from "node:path";
import * as fs from "node:fs";

export default function (pi: ExtensionAPI) {
    const pane = process.env.TMUX_PANE;
    if (!pane) return;

    let winId = "";
    let session = "unknown";
    let wname = "pi";

    try {
        const out = execSync(`tmux display-message -p -t "${pane}" '#{window_id}\t#{session_name}\t#{window_name}'`, { encoding: "utf8" }).trim();
        const parts = out.split("\t");
        if (parts.length === 3) {
            winId = parts[0];
            session = parts[1];
            wname = parts[2];
        }
    } catch (e) {
        return; // Not in a valid tmux session
    }

    if (!winId) return;

    // Helper to run tmux commands synchronously
    const tq = (cmd: string) => {
        try {
            return execSync(cmd, { encoding: "utf8" }).trim();
        } catch {
            return "";
        }
    };

    // Derive the WINDOW-level @claude_state from every pane's per-pane @claude_state.
    const recomputeWindowState = () => {
        const panesStr = tq(`tmux list-panes -t "${winId}" -F '#{pane_id} #{pane_current_command} #{@claude_state}'`);
        let best = "";
        let rank = 0;
        
        for (const line of panesStr.split("\n")) {
            if (!line.trim()) continue;
            const [pid, cmd, st] = line.split(" ");
            if (!st) continue;
            
            // Reusing claude/node/pi matching
            if (!["pi", "node", "claude"].includes(cmd)) {
                tq(`tmux set-option -pu -t "${pid}" @claude_state`);
                continue;
            }
            
            let r = 0;
            if (st === "permission") r = 5;
            else if (st === "working") r = 4;
            else if (st === "question") r = 3;
            else if (st === "idle") r = 2;
            else if (st === "done") r = 1;
            
            if (r > rank) {
                rank = r;
                best = st;
            }
        }
        
        if (best) {
            tq(`tmux set-option -w -t "${winId}" @claude_state "${best}"`);
        } else {
            tq(`tmux set-option -wu -t "${winId}" @claude_state`);
        }
    };

    // Update pane state, preserve custom names, update window color
    const windowStatus = (state: string) => {
        const cur = tq(`tmux show-options -pqv -t "${pane}" @claude_state`);
        if (cur === state) return;

        let base = tq(`tmux show-options -wqv -t "${winId}" @claude_base`);
        if (!base) {
            base = wname.replace(/^[^a-zA-Z0-9]+\s*/, "").trim();
            tq(`tmux set-option -w -t "${winId}" @claude_base "${base}"`);
        }

        tq(`tmux set-option -p -t "${pane}" @claude_state "${state}"`);
        recomputeWindowState();
        
        if (base) {
            tq(`tmux rename-window -t "${winId}" "${base}"`);
        }
    };

    // Clear state when pi exits
    const clearPaneState = () => {
        tq(`tmux set-option -pu -t "${pane}" @claude_state`);
        recomputeWindowState();
    };

    const notify = (msg: string) => {
        try {
            let label = tq(`tmux show-options -wqv -t "${winId}" @claude_base`);
            if (!label) label = wname.replace(/^[^a-zA-Z0-9]+\s*/, "").trim();
            const sub = label ? `${session} · ${label}` : session;
            
            const logo = path.join(process.env.HOME || "", ".claude/claude-logo.png");
            
            const args = [
                "-title", "Pi Agent",
                "-subtitle", sub,
                "-message", msg,
                "-sound", "Glass",
                "-group", `pi-${session}`
            ];
            if (fs.existsSync(logo)) {
                args.push("-contentImage", logo);
            }
            spawn("terminal-notifier", args, { stdio: "ignore", detached: true }).unref();
        } catch (e) {}
    };

    const alertTmux = () => {
        const logAlert = path.join(process.env.HOME || "", ".tmux/scripts/log-alert.sh");
        if (fs.existsSync(logAlert)) {
            try {
                execSync(`"${logAlert}" "${session}" "${winId}" "${wname}" PI`, { stdio: "ignore" });
            } catch {}
        }
    };

    const isDefaultName = (name: string) => {
        return /^(|zsh|-zsh|bash|-bash|sh|fish|node|claude|pi|login)$/.test(name);
    };

    const kebabShort = (text: string, maxWords: number) => {
        const words = text.toLowerCase()
            .replace(/[^a-z0-9 -]/g, "")
            .replace(/\s+/g, " ")
            .trim()
            .split(" ");
        return words.slice(0, maxWords).join("-");
    };

    const autonameCapture = (prompt: string, cwd: string) => {
        if (tq(`tmux show-options -wqv -t "${winId}" @claude_autoname_done`)) return;

        let ticket = "";
        try {
            const branch = execSync(`git -C "${cwd}" rev-parse --abbrev-ref HEAD`, { stdio: ["ignore", "pipe", "ignore"], encoding: "utf8" }).trim();
            const match = branch.match(/[A-Z]+-[0-9]+/);
            if (match) ticket = match[0];
        } catch { }

        // Take the first line of the user's prompt as the topic
        const topic = prompt.split('\n')[0].trim();
        if (!topic || topic.indexOf(" ") === -1 || isDefaultName(topic)) return;

        const max = ticket ? 3 : 4;
        const namePart = kebabShort(topic, max);
        const name = ticket ? `${ticket} ${namePart}` : namePart;

        tq(`tmux set-option -w -t "${winId}" @claude_autoname_done 1`);
        tq(`tmux set-option -w -t "${winId}" @claude_base "${name}"`);
    };

    // Hook Pi Events
    pi.on("before_agent_start", async (event, ctx) => {
        const stripped = wname.replace(/^[^a-zA-Z0-9]+\s*/, "").trim();
        if (!isDefaultName(stripped) && !tq(`tmux show-options -wqv -t "${winId}" @claude_autoname_done`)) {
            // User explicitly named it
            tq(`tmux set-option -w -t "${winId}" @claude_autoname_done 1`);
        }
        
        autonameCapture(event.prompt, ctx.cwd);
        windowStatus("working");
    });

    pi.on("agent_end", async (event, ctx) => {
        notify("Pi finished");
        
        let isQuestion = false;
        if (event.messages && event.messages.length > 0) {
            // Find the last assistant message
            for (let i = event.messages.length - 1; i >= 0; i--) {
                const msg = event.messages[i];
                if (msg.role === "assistant" && typeof msg.content === "string") {
                    const text = msg.content.trim().replace(/[\s*_`"']+$/, "");
                    if (text.endsWith("?")) {
                        isQuestion = true;
                    }
                    break;
                }
            }
        }
        
        if (isQuestion) {
            windowStatus("question");
        } else {
            windowStatus("done");
        }
        alertTmux();
    });

    // Handle project_trust permission prompt
    pi.on("project_trust", async () => {
        windowStatus("permission");
        notify("Pi requests permission");
        alertTmux();
        return { trusted: "undecided" }; // Let the built-in flow handle it
    });

    pi.on("session_shutdown", async () => {
        clearPaneState();
    });
}
