#!/usr/bin/env bash
# One-time, per machine: wires pi-subagents' user-level config to the factory.
# pi-subagents reads its config only from ~/.pi/agent/extensions/subagent/config.json,
# which applies to every repo, so the hook is a shim: it delegates to the repo's
# scripts/factory/worktree-hook.mjs when present and does nothing elsewhere.
# Idempotent; backs up the config before changing it.
set -euo pipefail
cfg_dir="$HOME/.pi/agent/extensions/subagent"
cfg="$cfg_dir/config.json"
shim="$cfg_dir/factory-worktree-hook.mjs"
mkdir -p "$cfg_dir"

cat > "$shim" <<'SHIM'
#!/usr/bin/env node
// Factory shim (installed by scripts/factory/install-pi-config.sh).
// Finds the factory project the agent runs in: the repo root, or a folder of a
// monorepo (D56), and delegates to its scripts/factory/worktree-hook.mjs.
import { existsSync } from "node:fs";
import { join, relative, dirname, isAbsolute } from "node:path";
import { spawnSync } from "node:child_process";
const data = await new Promise((r) => { let d = ""; process.stdin.on("data", (c) => (d += c)); process.stdin.on("end", () => r(d)); });
const { repoRoot, worktreePath, agentCwd } = JSON.parse(data);
const inside = (base, p) => p && base && !relative(base, p).startsWith("..") && !isAbsolute(relative(base, p));
let rel = inside(worktreePath, agentCwd) ? relative(worktreePath, agentCwd) : inside(repoRoot, agentCwd) ? relative(repoRoot, agentCwd) : "";
for (;;) {
  if (existsSync(join(repoRoot, rel, "scripts/factory/worktree-hook.mjs"))) break;
  if (!rel || rel === ".") { process.stdout.write('{"syntheticPaths":[]}'); process.exit(0); }
  rel = dirname(rel) === "." ? "" : dirname(rel);
}
const hook = join(repoRoot, rel, "scripts/factory/worktree-hook.mjs");
const r = spawnSync(process.execPath, [hook], { input: data, encoding: "utf8", env: { ...process.env, FACTORY_PROJECT_PREFIX: rel } });
process.stderr.write(r.stderr || ""); process.stdout.write(r.stdout || ""); process.exit(r.status ?? 1);
SHIM

[ -f "$cfg" ] && cp "$cfg" "$cfg.bak.$(date +%Y%m%d%H%M%S)"
node - "$cfg" "$shim" <<'NODE'
const fs = require("fs");
const [cfg, shim] = process.argv.slice(2);
const c = fs.existsSync(cfg) ? JSON.parse(fs.readFileSync(cfg, "utf8")) : {};
c.worktreeSetupHook = shim;
c.parallel = { ...(c.parallel || {}), concurrency: (c.parallel && c.parallel.concurrency) || 4 };
fs.writeFileSync(cfg, JSON.stringify(c, null, 2) + "\n");
console.log(`Updated ${cfg}: worktreeSetupHook → shim, parallel.concurrency = ${c.parallel.concurrency}`);
NODE
