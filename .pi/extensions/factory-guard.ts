// pi-factory command guard (ADR-001 D51). Blocks dangerous tool calls by any
// agent working in this repo: the lead and every factory subagent.
// Rules and their tests: scripts/factory/guard-rules.mjs, tests/guard.test.mjs.
// Project extensions load once the project is trusted in Pi; doctor.sh checks
// the file is here, and patch-guard.sh is the backstop at integration.
import { appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { check } from "../../scripts/factory/guard-rules.mjs";

export default function (pi: any) {
  pi.on("tool_call", async (event: any, ctx: any) => {
    const cwd = ctx?.cwd ?? process.cwd();
    const hit = check({ tool: event.toolName, input: event.input, cwd });
    if (!hit) return;
    try {
      const dir = join(cwd, ".pi-subagents");
      mkdirSync(dir, { recursive: true });
      appendFileSync(join(dir, "guard.log"),
        `${new Date().toISOString()}\t${hit.rule}\t${event.toolName}\t${JSON.stringify(event.input).slice(0, 300)}\n`);
    } catch { /* logging is best-effort */ }
    return { block: true, reason: `${hit.reason}. If this is really needed, stop and ask the human.` };
  });
}
