import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as path from "node:path";
import * as fs from "node:fs/promises";
import * as os from "node:os";

export default function (pi: ExtensionAPI) {
    pi.on("resources_discover", async (event, _ctx) => {
        const pathsToReturn: string[] = [];
        
        // 1. Project-local .claude/skills
        const localClaudeSkillsPath = path.join(event.cwd, ".claude/skills");
        try {
            await fs.access(localClaudeSkillsPath);
            pathsToReturn.push(localClaudeSkillsPath);
        } catch {
            // ignore
        }

        // 2. Global ~/.claude/skills (Local global skills)
        const globalClaudeSkillsPath = path.join(os.homedir(), ".claude/skills");
        try {
            await fs.access(globalClaudeSkillsPath);
            pathsToReturn.push(globalClaudeSkillsPath);
        } catch {
            // ignore
        }

        // 3. Claude Code marketplace plugins — only the ones that are enabled in
        // ~/.claude/plugins/installed_plugins.json (keys look like
        // "general@gtech-skills"), the same set Claude Code loads. Packages that
        // merely exist in a marketplace checkout are skipped.
        const pluginsRoot = path.join(os.homedir(), ".claude/plugins");
        try {
            const raw = await fs.readFile(path.join(pluginsRoot, "installed_plugins.json"), "utf8");
            const installed = JSON.parse(raw) as { plugins?: Record<string, unknown> };
            for (const key of Object.keys(installed.plugins ?? {})) {
                const at = key.lastIndexOf("@");
                if (at <= 0) continue;
                const plugin = key.slice(0, at);
                const marketplace = key.slice(at + 1);
                const skillDir = path.join(pluginsRoot, "marketplaces", marketplace, plugin, "skills");
                try {
                    await fs.access(skillDir);
                    pathsToReturn.push(skillDir);
                } catch {
                    // This plugin has no skills directory
                }
            }
        } catch {
            // No installed_plugins.json
        }

        return {
            skillPaths: pathsToReturn,
        };
    });
}
