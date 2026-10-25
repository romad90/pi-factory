#!/usr/bin/env node
// pi-subagents worktreeSetupHook for the factory (D35). Runs once per worker
// worktree the package creates:
//   - hides instrument/ with a sparse checkout, so workers can't see the
//     cases they'll be judged on (D21). Tracked files can't be declared
//     synthetic, but sparse-checkout keeps them out of the working tree
//     without showing up as deletions in the captured patch;
//   - writes .env.factory with a per-worktree bot port (D27);
//   - gives the worker the installed dependencies (D65): links the main
//     checkout's dependency folders (FACTORY_DEPS_LINKS, default
//     "node_modules .venv"; in a monorepo both the project's and the repo
//     root's), or runs FACTORY_DEPS_CMD in the worktree when it is set. A
//     worker that can't run the tests can't check its own work.
// Settings come from the environment, then the project's .factory/commands.env.
// stdin: { repoRoot, worktreePath, agentCwd, branch, index, runId, baseCommit }
// stdout: { "syntheticPaths": [...] }
import { execFileSync, execSync } from "node:child_process";
import { existsSync, lstatSync, mkdirSync, readFileSync, readlinkSync, realpathSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

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

// FACTORY_X from the environment, else the last FACTORY_X=... line of commands.env.
const commandsEnv = (() => {
  try { return readFileSync(join(input.repoRoot, prefix, ".factory/commands.env"), "utf8"); } catch { return ""; }
})();
const setting = (name, dflt) => {
  if (process.env[name] !== undefined) return process.env[name];
  const re = new RegExp(`^\\s*(?:export\\s+)?${name}=(.*)$`);
  let v;
  for (const line of commandsEnv.split("\n")) {
    const m = line.match(re);
    if (m) v = m[1].trim().replace(/^(["'])(.*)\1$/, "$2");
  }
  return v === undefined ? dflt : v;
};
const exists = (p) => { try { lstatSync(p); return true; } catch { return false; } };

// factory setup (D102) rehearses without it: no instrument to hide, and no worktreeConfig turned on.
if (process.env.FACTORY_HOOK_NO_SPARSE !== "1") execFileSync("git", ["-C", wt, "sparse-checkout", "set", "--no-cone", "/*", `!/${pattern(inProject(instrument))}/`], { stdio: "ignore" });
writeFileSync(join(wt, prefix, ".env.factory"), `BOT_PORT=${base + Number(input.index ?? 0)}\n`);

const synthetic = [inProject(".env.factory")];
const depsCmd = setting("FACTORY_DEPS_CMD", "");
if (depsCmd) {
  // A real install, isolated per worktree. Its output goes to stderr: stdout is the hook's answer.
  execSync(depsCmd, { cwd: join(wt, prefix), stdio: ["ignore", 2, 2], shell: "/bin/bash" });
} else {
  const names = setting("FACTORY_DEPS_LINKS", "node_modules .venv").split(/\s+/).filter(Boolean);
  const dirs = prefix ? [prefix, ""] : [""];
  for (const d of dirs) for (const n of names) {
    const from = join(input.repoRoot, d, n), to = join(wt, d, n);
    if (!existsSync(from) || exists(to)) continue;   // nothing installed, or tracked/already there
    symlinkSync(from, to, "dir");
    synthetic.push(d ? `${d}/${n}` : n);
  }
}

// D92: a project on the installed package reaches the factory through local,
// untracked links (link.sh); a worktree only has tracked files, so it gets
// the same links, kept out of the patch.
const here = dirname(realpathSync(fileURLToPath(import.meta.url)));
const linkList = (() => { try { return readFileSync(join(here, "package-links.txt"), "utf8"); } catch { return ""; } })();
for (const rel of linkList.split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("#"))) {
  const from = join(input.repoRoot, prefix, rel), to = join(wt, prefix, rel);
  let isLink = false; try { isLink = lstatSync(from).isSymbolicLink(); } catch {}
  if (!isLink || exists(to)) continue;
  mkdirSync(dirname(to), { recursive: true });
  symlinkSync(readlinkSync(from), to);
  synthetic.push(inProject(rel));
}

process.stdout.write(JSON.stringify({ syntheticPaths: synthetic }));
