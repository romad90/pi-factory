#!/usr/bin/env bash
# Tokens and cost per subagent run (D85), from the per-run metadata
# pi-subagents writes ({runId}_{agent}_meta.json: usage, model, duration).
# Appends the runs not seen yet to .scratch/<mission>/usage.tsv; metrics.sh
# sums them. Best effort: no metadata found means nothing to add.
#
# Usage: scripts/factory/usage.sh <feature>
# Roots searched: $FACTORY_USAGE_DIRS (space-separated), else .pi/subagents,
# ~/.pi/agent and the temp folder.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: usage.sh <feature>}"
dir="$(mission_dir "$feature")"
[ -f "$dir/spec.md" ] || die "no mission '$feature'"
out="$dir/usage.tsv"
read -r -a roots <<<"${FACTORY_USAGE_DIRS:-.pi/subagents $HOME/.pi/agent ${TMPDIR:-/tmp}}"
existing=()
for r in "${roots[@]}"; do [ -d "$r" ] && existing+=("$r"); done
[ ${#existing[@]} -gt 0 ] || exit 0
find "${existing[@]}" -maxdepth 7 -type f -name '*_meta.json' -newer "$dir/spec.md" 2>/dev/null \
  | node -e '
const fs = require("fs"); const out = process.argv[1];
const files = fs.readFileSync(0, "utf8").split("\n").filter(Boolean);
const seen = new Set();
if (fs.existsSync(out)) for (const l of fs.readFileSync(out, "utf8").split("\n").slice(1)) if (l) seen.add(l.split("\t")[1]);
let add = "";
for (const f of files) {
  let j; try { j = JSON.parse(fs.readFileSync(f, "utf8")); } catch { continue; }
  const base = f.split("/").pop().replace(/_meta\.json$/, "");
  const i = base.indexOf("_"); const runId = j.runId || (i > 0 ? base.slice(0, i) : base);
  const agent = j.agent || (i > 0 ? base.slice(i + 1) : "?");
  if (!String(agent).startsWith("factory-") || seen.has(runId)) continue;
  const u = j.usage || {}; seen.add(runId);
  const when = new Date(fs.statSync(f).mtimeMs).toISOString().slice(0, 16).replace("T", " ");
  add += [when, runId, agent, j.model || "", u.input || 0, u.output || 0, u.cacheRead || 0, u.cacheWrite || 0, u.cost || 0, u.turns || 0, j.durationMs || 0].join("\t") + "\n";
}
if (add) {
  if (!fs.existsSync(out)) fs.writeFileSync(out, "date\trun\tagent\tmodel\tinput\toutput\tcache_read\tcache_write\tcost\tturns\tduration_ms\n");
  fs.appendFileSync(out, add);
}
process.stdout.write(add ? `usage: ${add.trim().split("\n").length} run(s) added to ${out}\n` : "usage: nothing new\n");
' "$out"
