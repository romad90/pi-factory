#!/usr/bin/env node
// pi-subagents worktreeSetupHook for the factory (D35). Runs once per worker
// worktree the package creates:
//   - hides instrument/ with a sparse checkout, so workers can't see the
//     cases they'll be judged on (D21). Tracked files can't be declared
//     synthetic, but sparse-checkout keeps them out of the working tree
//     without showing up as deletions in the captured patch;
//   - writes .env.factory with a per-worktree bot port (D27).
// stdin: { repoRoot, worktreePath, agentCwd, branch, index, runId, baseCommit }
// stdout: { "syntheticPaths": [...] }
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { join } from "node:path";

const input = JSON.parse(await new Promise((res) => {
  let d = ""; process.stdin.on("data", (c) => (d += c)); process.stdin.on("end", () => res(d));
}));
const wt = input.worktreePath;
// In a monorepo the project is a folder of the worktree (D56); the shim passes it.
const prefix = (process.env.FACTORY_PROJECT_PREFIX || "").replace(/\/+$/, "");
const inProject = (p) => (prefix ? `${prefix}/${p}` : p);
const pattern = (p) => p.replace(/[\\*?[\]!#]/g, "\\$&");   // gitignore-style special characters
const instrument = process.env.FACTORY_INSTRUMENT_DIR || "instrument";
const base = Number(process.env.FACTORY_PORT_BASE || 8100);

execFileSync("git", ["-C", wt, "sparse-checkout", "set", "--no-cone", "/*", `!/${pattern(inProject(instrument))}/`], { stdio: "ignore" });
writeFileSync(join(wt, prefix, ".env.factory"), `BOT_PORT=${base + Number(input.index ?? 0)}\n`);

process.stdout.write(JSON.stringify({ syntheticPaths: [inProject(".env.factory")] }));
