import { exec, execSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as path from "node:path";
import * as fs from "node:fs";

export default function (pi: ExtensionAPI) {
    pi.on("agent_start", async (_event, ctx) => {
        // ...
    });
}
