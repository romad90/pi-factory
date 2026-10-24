// pi-factory command guard (ADR-001 D51). Blocks dangerous tool calls by any
// agent working in this repo: the lead and every factory subagent.
// Rules and their tests: scripts/factory/guard-rules.mjs, tests/guard.test.mjs.
// Project extensions load once the project is trusted in Pi; doctor.sh checks
// the file is here, and patch-guard.sh is the backstop at integration.
//
// D100: the hands hold no secrets. Every bash call in a factory project runs
// with credential-like variables unset (secretEnvNames), so a command, a test
// or an injected instruction finds no key in its environment. The harness
// process keeps its own environment to call the model.
//
// D101: FACTORY_TOOL_ENV_KEEP comes from the harness's own environment only:
// a project file an agent could edit never decides what the hands keep, and
// the keep list never brings back the gateway or a models.json key. Refusals
// are logged redacted (redact.mjs, shared with the run archive).
import { appendFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { agentDir, check, inFactoryProject, scrubCommand, secretEnvNames } from "../../scripts/factory/guard-rules.mjs";
import { redact } from "../../scripts/factory/redact.mjs";

// FACTORY_GATEWAY_KEY_ENV: environment first, then the project's
// .factory/commands.env (last assignment wins). It only adds a name to scrub.
function projectSetting(cwd: string, name: string): string | undefined {
  if (process.env[name] !== undefined) return process.env[name];
  for (let d = resolve(cwd); ; d = dirname(d)) {
    const f = join(d, ".factory", "commands.env");
    if (existsSync(f)) {
      let v: string | undefined;
      const re = new RegExp(`^\\s*(?:export\\s+)?${name}=(.*)$`);
      for (const line of readFileSync(f, "utf8").split("\n")) {
        const m = line.match(re);
        if (m) v = m[1].trim().replace(/^(["'])(.*)\1$/, "$2");
      }
      return v;
    }
    if (dirname(d) === d) return undefined;
  }
}

function modelsJson(): unknown {
  try { return JSON.parse(readFileSync(join(agentDir(), "models.json"), "utf8")); } catch { return null; }
}

// The logged input: redacted first, then cut (a cut must not split a secret
// into a piece the patterns no longer recognize).
const logged = (input: unknown) => redact(JSON.stringify(input) ?? "").slice(0, 300).replace(/[\t\n]/g, " ");

export default function (pi: any) {
  pi.on("tool_call", async (event: any, ctx: any) => {
    const cwd = ctx?.cwd ?? process.cwd();
    const hit = check({ tool: event.toolName, input: event.input, cwd });
    if (hit) {
      try {
        const dir = join(cwd, ".pi-subagents");
        mkdirSync(dir, { recursive: true });
        appendFileSync(join(dir, "guard.log"),
          `${new Date().toISOString()}\t${hit.rule}\t${event.toolName}\t${logged(event.input)}\n`);
      } catch { /* logging is best-effort */ }
      try {
        // D97: also in the git folder all worktrees share, so the refusal
        // outlives the worker's worktree and the run archive can attach it.
        const common = resolve(cwd, execFileSync("git", ["rev-parse", "--git-common-dir"], { cwd, encoding: "utf8" }).trim());
        const dir = join(common, "pi-factory");
        mkdirSync(dir, { recursive: true });
        appendFileSync(join(dir, "guard.log"),
          `${new Date().toISOString()}\t${hit.rule}\t${event.toolName}\t${logged(event.input)}\t${cwd}\n`);
      } catch { /* outside a git repo: nothing to attach to */ }
      return { block: true, reason: `${hit.reason}. If this is really needed, stop and ask the human.` };
    }
    if (event.toolName === "bash" && typeof event.input?.command === "string" && inFactoryProject(cwd)) {
      const env = { ...process.env } as Record<string, string | undefined>;
      const gw = projectSetting(cwd, "FACTORY_GATEWAY_KEY_ENV");
      if (gw) env.FACTORY_GATEWAY_KEY_ENV = gw;
      // FACTORY_TOOL_ENV_KEEP: process.env only (never commands.env).
      event.input.command = scrubCommand(event.input.command, secretEnvNames({ env, modelsJson: modelsJson() }));
    }
    return undefined;
  });
}
