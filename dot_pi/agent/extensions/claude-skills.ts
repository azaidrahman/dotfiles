import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as path from "node:path";
import * as fs from "node:fs/promises";
import * as os from "node:os";

// Give the skills directory of the newest cached version of one plugin. Give
// null when no version holds skills. The cache path of a plugin is
// ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/. A plugin update
// writes a new version directory and leaves the old one, so compare the times.
async function newestSkillDir(pluginDir: string): Promise<string | null> {
    let versions: string[];
    try {
        versions = await fs.readdir(pluginDir);
    } catch {
        return null;
    }

    const candidates = await Promise.all(versions.map(async (version) => {
        const versionDir = path.join(pluginDir, version);
        try {
            const stats = await fs.stat(versionDir);
            if (!stats.isDirectory()) return null;
            const skillDir = path.join(versionDir, "skills");
            await fs.access(skillDir);
            return { skillDir, mtimeMs: stats.mtimeMs };
        } catch {
            // This version is gone, or it has no skills directory
            return null;
        }
    }));

    const found = candidates.filter((c) => c !== null);
    if (found.length === 0) return null;
    found.sort((a, b) => b.mtimeMs - a.mtimeMs);
    return found[0].skillDir;
}

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
        //
        // Read the plugin cache, not the marketplace checkout. A marketplace
        // holds its plugins under any path it likes, and a plugin that comes
        // from a URL has no checkout at all. The cache is the one place that
        // holds every installed plugin.
        const pluginsRoot = path.join(os.homedir(), ".claude/plugins");
        try {
            const raw = await fs.readFile(path.join(pluginsRoot, "installed_plugins.json"), "utf8");
            const installed = JSON.parse(raw) as { plugins?: Record<string, unknown> };
            for (const key of Object.keys(installed.plugins ?? {})) {
                const at = key.lastIndexOf("@");
                if (at <= 0) continue;
                const plugin = key.slice(0, at);
                const marketplace = key.slice(at + 1);
                const skillDir = await newestSkillDir(path.join(pluginsRoot, "cache", marketplace, plugin));
                if (skillDir !== null) {
                    pathsToReturn.push(skillDir);
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
