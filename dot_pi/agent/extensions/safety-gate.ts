import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { fireNotify } from "../lib/notify-hook";

export default function (pi: ExtensionAPI) {
	// List of regex patterns to match against dangerous bash commands
	const dangerousPatterns = [
		// File Deletion (recursive/forced only — plain `rm file` is allowed)
		/\brm\b\s+-\w*[rRf]/i,  // Catch recursive/forced rm (rm -rf, rm -fr, rm -r, rm -f)

		// Infrastructure
		/\bterraform\s+(apply\s+-destroy|destroy)\b/i,
		/\bgcloud\s+[\w-\s]*delete\b/i,
		/\bkubectl\s+delete\b/i,
		/\baws\s+[\w-\s]*delete\b/i,
		
		// Databases & SQL Commands
		/\bDROP\s+(TABLE|DATABASE|SCHEMA|INDEX|VIEW|USER|ROLE)\b/i,
		/\bTRUNCATE\s+TABLE\b/i,
		/\bDELETE\s+FROM\b/i,   // Catch generic SQL deletes

		// Containers
		/\b(docker|podman)\s+(rm|rmi|system\s+prune|volume\s+rm|network\s+rm)\b/i,

		// System & Permissions
		/\bsudo\b/i,
		/\bchmod\b\s+-(R)?\s*777/i,
		/\bchown\b\s+-R/i,
		
		// Dangerous Disk/System Binaries
		/\bdd\s+if=/i,
		/\bmkfs(\.\w+)?\b/i
	];

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;

		const command = event.input.command as string;
		const matchedPattern = dangerousPatterns.find((p) => p.test(command));

		if (matchedPattern) {
			if (!ctx.hasUI) {
				// In non-interactive mode, block by default
				return { 
					block: true, 
					reason: `Dangerous command blocked automatically in non-interactive mode. Matched: ${matchedPattern}` 
				};
			}

			// Interactive prompt. Tell the shared hook first, so the tmux window
			// turns red and the phone buzzes if you are away.
			fireNotify("permission_prompt", { message: `pi wants to run: ${command}` });
			const choice = await ctx.ui.select(
				`⚠️ DANGEROUS COMMAND DETECTED ⚠️\n\nPattern matched: ${matchedPattern}\nCommand:\n  ${command}\n\nAllow execution?`, 
				["No, Block It", "Yes, Allow It"]
			);

			if (choice !== "Yes, Allow It") {
				return { block: true, reason: "Command execution blocked by user." };
			}
		}

		return undefined;
	});
}
