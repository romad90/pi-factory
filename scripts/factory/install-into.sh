#!/usr/bin/env bash
# Installs (or updates) the factory into another repo, from the pi-factory
# template repo. Safe to re-run: never overwrites a file you changed in the
# target without saying so, never touches your CI file.
#
# Usage (from the template repo root):
#   scripts/factory/install-into.sh <path-to-target-repo>
set -euo pipefail

src="$(cd "$(dirname "$0")/../.." && pwd)"
dst="${1:?usage: install-into.sh <path-to-target-repo>}"
dst="$(cd "$dst" && pwd)"
[ "$src" != "$dst" ] || { echo "target is the template repo itself"; exit 2; }
git -C "$dst" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "$dst is not a git repo"; exit 2; }

added=0; updated=0; kept=0
note() { printf '  %s\n' "$*"; }

# Copy one file. Template-owned files are refreshed; repo-owned files
# (settings you fill per repo) are created once and then left alone.
put() {                                   # <relative path> <owned: template|repo>
  local rel="$1" owner="$2" s="$src/$1" d="$dst/$1"
  mkdir -p "$(dirname "$d")"
  if [ ! -e "$d" ]; then cp "$s" "$d"; added=$((added + 1)); return; fi
  cmp -s "$s" "$d" && return
  if [ "$owner" = template ]; then cp "$s" "$d"; updated=$((updated + 1))
  else kept=$((kept + 1)); note "kept your $rel (repo-specific; compare with the template if needed)"; fi
}
put_tree() {                              # <relative dir> <owner>
  local f
  while IFS= read -r f; do put "$f" "$2"; done < <(cd "$src" && find "$1" -type f)
}

echo "Installing the factory into $dst"

# Template-owned: refreshed on every run.
put_tree .pi/agents/factory template
put_tree .pi/skills template
put .pi/prompts/factory.md template
put .pi/prompts/factory-light.md template
put_tree scripts/factory template
put_tree .factory/briefs template
put_tree .factory/skills-pin template
put .factory/model-families.json template
for f in contract-format.md verdict-format.md contract-checklist-bots.md bot-harness.md; do
  put "docs/agents/$f" template
done
mkdir -p "$dst/docs/factory"
cp "$src/docs/adr/ADR-001-agentic-factory.md" "$dst/docs/factory/ADR-001-agentic-factory.md"

# Repo-owned: created once, then yours.
put .factory/commands.env repo
put .factory/behavior-paths repo
mkdir -p "$dst/instrument/scenarios"
[ -n "$(ls -A "$dst/instrument/scenarios")" ] || : > "$dst/instrument/scenarios/.gitkeep"

# .pi/settings.json: add the factory's "subagents" block, keep everything else.
node - "$src/.pi/settings.json" "$dst/.pi/settings.json" <<'NODE'
const fs = require("fs");
const [srcFile, dstFile] = process.argv.slice(2);
const tpl = JSON.parse(fs.readFileSync(srcFile, "utf8"));
const cur = fs.existsSync(dstFile) ? JSON.parse(fs.readFileSync(dstFile, "utf8")) : {};
const had = !!cur.subagents;
cur.subagents = { ...tpl.subagents, ...(cur.subagents || {}),
  agentOverrides: { ...tpl.subagents.agentOverrides, ...((cur.subagents || {}).agentOverrides || {}) } };
fs.mkdirSync(require("path").dirname(dstFile), { recursive: true });
fs.writeFileSync(dstFile, JSON.stringify(cur, null, 2) + "\n");
console.log(`  .pi/settings.json: ${had ? "merged (your existing subagents values kept)" : "factory subagents block added"}`);
NODE

# .gitignore: append missing lines.
touch "$dst/.gitignore"
for line in "instrument/results/" ".env.factory" ".pi-subagents/"; do
  grep -qxF "$line" "$dst/.gitignore" || { printf '%s\n' "$line" >> "$dst/.gitignore"; note ".gitignore += $line"; }
done

# AGENTS.md: append the factory section once.
touch "$dst/AGENTS.md"
if grep -q '^## Agentic factory' "$dst/AGENTS.md"; then
  note "AGENTS.md already has the factory section (left as is)"
else
  { echo; sed '/^<!--/,/-->$/d' "$src/AGENTS.factory.md"; } >> "$dst/AGENTS.md"
  note "AGENTS.md += factory section"
fi

# Legacy .agents/ markdown would be loaded as agents by pi-subagents.
if [ -d "$dst/.agents" ] && find "$dst/.agents" -name '*.md' | grep -q .; then
  note "WARNING: $dst/.agents/ contains markdown: pi-subagents will load it as agents. Move those skills to .pi/skills/."
fi

echo "  files: $added added, $updated updated, $kept kept"
echo
(cd "$dst" && bash scripts/factory/skills-pin.sh verify | tail -1 && node scripts/factory/models-lint.mjs | tail -1) || true

cat <<MSG

Left for you in $dst:
  1. .factory/commands.env      lint and test commands of this repo
  2. .factory/behavior-paths    which paths change the bot's behavior
  3. .gitlab-ci.yml             merge the factory jobs from the template (not touched)
  4. GitLab                     enable "Pipelines must succeed"
  5. /setup-matt-pocock-skills  local markdown tracker in .scratch/
Then, in Pi from $dst: /subagents-models (7 factory-* agents, no skills as agents).
MSG
