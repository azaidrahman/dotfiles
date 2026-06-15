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

        // 3. Claude Code Marketplaces (e.g. gtech-skills plugin tree)
        // We'll search one level deep in the gtech-skills packages
        const marketplacesPath = path.join(os.homedir(), ".claude/plugins/marketplaces/gtech-skills");
        try {
            const packages = await fs.readdir(marketplacesPath, { withFileTypes: true });
            for (const pkg of packages) {
                if (pkg.isDirectory() && !pkg.name.startsWith(".")) {
                    const skillDir = path.join(marketplacesPath, pkg.name, "skills");
                    try {
                        await fs.access(skillDir);
                        pathsToReturn.push(skillDir);
                    } catch {
                        // This package doesn't have a skills directory
                    }
                }
            }
        } catch {
            // No marketplaces directory found
        }

        return {
            skillPaths: pathsToReturn,
        };
    });
}
