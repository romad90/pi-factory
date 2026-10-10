#!/usr/bin/env bash
# Installs (or updates) the factory into another repo, from the pi-factory
# template repo. Safe to re-run: never overwrites a file you changed in the
# target without saying so, never touches your CI file.
#
# By default the install lands on its own branch and commit
# (chore/install-pi-factory-<version>), so it goes through its own MR and
# feature MRs stay feature-sized (D48).
#
# Usage (from the template repo root):
#   scripts/factory/install-into.sh <path-to-target-repo> [--no-branch]
set -euo pipefail

src="$(cd "$(dirname "$0")/../.." && pwd)"
dst="${1:?usage: install-into.sh <path-to-target-repo> [--no-branch]}"
branch_mode=1; [ "${2:-}" = "--no-branch" ] && branch_mode=0
dst="$(cd "$dst" && pwd)"
[ "$src" != "$dst" ] || { echo "target is the template repo itself"; exit 2; }
git -C "$dst" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "$dst is not a git repo"; exit 2; }
version="$(cat "$src/.factory/VERSION" 2>/dev/null || echo dev)"

if [ "$branch_mode" -eq 1 ]; then
  [ -z "$(git -C "$dst" status --porcelain)" ] || { echo "$dst has uncommitted changes: commit or stash them, or pass --no-branch"; exit 2; }
  br="chore/install-pi-factory-$version"
  if [ "$(git -C "$dst" branch --show-current)" != "$br" ]; then
    git -C "$dst" switch -q -c "$br" 2>/dev/null || git -C "$dst" switch -q "$br"
  fi
  echo "On branch $br in $dst"
fi

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
for f in "$src"/.pi/prompts/factory*.md; do put ".pi/prompts/$(basename "$f")" template; done
put_tree scripts/factory template
put_tree .factory/briefs template
put_tree .factory/skills-pin template
put .factory/model-families.json template
put .factory/VERSION template
mkdir -p "$dst/.factory/ci"
cp "$src/templates/gitlab/factory.gitlab-ci.yml" "$dst/.factory/ci/factory.gitlab-ci.yml"
for f in contract-format.md verdict-format.md contract-checklist-bots.md bot-harness.md; do
  put "docs/agents/$f" template
done
mkdir -p "$dst/docs/factory"
cp "$src/docs/adr/ADR-001-agentic-factory.md" "$dst/docs/factory/ADR-001-agentic-factory.md"
cp "$src/CHEATSHEET.md" "$dst/docs/factory/CHEATSHEET.md"

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
const { agentOverrides: _ignored, ...tplSub } = tpl.subagents;          // models live in agent frontmatter (D31)
cur.subagents = { ...tplSub, ...(cur.subagents || {}) };
const ov = cur.subagents.agentOverrides || {};
for (const k of Object.keys(ov)) if (k.startsWith("factory-")) delete ov[k];  // would crash pi-subagents
if (cur.subagents.agentOverrides && !Object.keys(ov).length) delete cur.subagents.agentOverrides;
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

committed=""
if [ "$branch_mode" -eq 1 ]; then
  git -C "$dst" add -A
  if ! git -C "$dst" diff --cached --quiet; then
    git -C "$dst" commit -q -m "chore(factory): install pi-factory $version" \
      -m "Installed by pi-factory scripts/factory/install-into.sh. Tooling only, no feature change."
    committed="$(git -C "$dst" rev-parse --short HEAD)"
  fi
fi

cat <<MSG

${committed:+Committed $committed on $br. Push it and open its own MR before any mission (D48).
}
Left for you in $dst:
  1. .factory/commands.env      FACTORY_TEST_CMD (required), lint, extra check, gateway URL
  2. .factory/behavior-paths    which paths change the bot's behavior
  3. .gitlab-ci.yml             add:  include: [{ local: .factory/ci/factory.gitlab-ci.yml }]
  4. GitLab                     enable "Pipelines must succeed"
  5. /setup-matt-pocock-skills  local markdown tracker in .scratch/
Then, in Pi from $dst: scripts/factory/doctor.sh, /subagents-models (7 factory-* agents).
Cheat sheet: docs/factory/CHEATSHEET.md
MSG
