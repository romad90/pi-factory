#!/usr/bin/env bash
# Onboards a project on the factory installed once per machine (P11, D92).
# Writes only what belongs to the project and links the rest. It never
# commits; with --migrate it stages the removal of the copied files (git rm).
#   project-owned, created once: .factory/commands.env, behavior-paths,
#     model-families.json, docs/agents/quality-bar.md, GLOSSARY.md (stub),
#     instrument/scenarios/, the AGENTS.md pointer, .gitignore lines,
#     the .pi/settings.json subagents block
#   refreshed: .factory/VERSION (the factory version this project expects),
#     .factory/package-sha (the factory commit CI fetches and checks),
#     .factory/ci/factory.gitlab-ci.yml
#   linked, untracked: scripts/factory, briefs, skills pin, the factory's
#     docs/agents files (link.sh); agents, prompts, skills and the command
#     guard load from the package itself
#
# Usage, from the project folder (a monorepo project: its own folder):
#   <package>/scripts/factory/onboard.sh [--ci mr|child] [--migrate]
#   --migrate   the factory was copied in by install-into.sh: remove the copies
#               (git rm), keep the project's own files, then onboard. One MR.
# Run again after upgrading the package: it bumps .factory/VERSION and the CI.
set -euo pipefail
here="$(cd -P "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"
pkg="$FACTORY_PACKAGE_ROOT"

ci_mode=mr; migrate=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ci) case "${2:-}" in mr|child) ci_mode="$2"; shift 2 ;; *) die "--ci takes mr or child" ;; esac ;;
    --migrate) migrate=1; shift ;;
    *) die "unknown option: $1" ;;
  esac
done
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not in a git repository"
[ "$(cd -P . && pwd)" != "$pkg" ] || die "this is the factory itself: run from the project to onboard"
prefix="$(git rev-parse --show-prefix)"; prefix="${prefix%/}"
version="$(cat "$pkg/.factory/VERSION")"
note() { printf '  %s\n' "$*"; }

# Copied by install-into.sh: those files must go first, or they shadow the package.
copied=(scripts/factory .factory/briefs .factory/skills-pin .pi/agents/factory .pi/extensions/factory-guard.ts docs/factory
        docs/agents/factory.md docs/agents/contract-format.md docs/agents/verdict-format.md docs/agents/bot-harness.md docs/agents/ticket-format.md)
for f in "$pkg"/.pi/prompts/factory*.md; do copied+=(".pi/prompts/$(basename "$f")"); done
for d in "$pkg"/.pi/skills/*/; do copied+=(".pi/skills/$(basename "$d")"); done
tracked="$(git ls-files -- "${copied[@]}" | sed -n 1p)"
if [ -n "$tracked" ]; then
  [ "$migrate" -eq 1 ] || die "the factory is copied into this project ($tracked …): run with --migrate to remove the copies, on its own branch"
  [ -z "$(git status --porcelain -- .)" ] || die "uncommitted changes: commit or stash them first"
  git rm -r -q --ignore-unmatch -- "${copied[@]}"
  note "removed the copied factory files (git rm); the project's own files stay"
fi

echo "Onboarding ${prefix:-this repository} on pi-factory $version ($pkg)"
put() {                                   # <relative path> [source path in the package]
  local rel="$1" from="$pkg/${2:-$1}"
  [ -e "$rel" ] && return 0
  mkdir -p "$(dirname "$rel")"; cp "$from" "$rel"; note "+ $rel"
}
put .factory/commands.env
put .factory/behavior-paths
put .factory/model-families.json
put docs/agents/quality-bar.md
mkdir -p instrument/scenarios
[ -n "$(ls -A instrument/scenarios)" ] || { : > instrument/scenarios/.gitkeep; note "+ instrument/scenarios/"; }
[ -e GLOSSARY.md ] || { printf '# Glossary\n\nThe domain terms of this project, one per line: **Term**: what it means here.\n' > GLOSSARY.md; note "+ GLOSSARY.md (stub)"; }
# CI fetches the factory at this commit and checks it before running it (D92).
if sha="$(git -C "$pkg" rev-parse HEAD 2>/dev/null)"; then
  [ -z "$(git -C "$pkg" status --porcelain --untracked-files=no)" ] || note "WARNING: the factory checkout has local changes; CI runs $sha without them"
  printf '%s\n' "$sha" > .factory/package-sha
else
  note "the factory is not a git checkout: write the pi-factory commit CI must run into .factory/package-sha"
fi
old="$(cat .factory/VERSION 2>/dev/null || true)"
printf '%s\n' "$version" > .factory/VERSION
[ "$old" = "$version" ] || note ".factory/VERSION: ${old:-none} → $version"
node "$pkg/scripts/factory/project-files.cjs" settings "$pkg/.pi/settings.json" .pi/settings.json "$prefix" --package
mkdir -p .factory/ci
node "$pkg/scripts/factory/project-files.cjs" ci "$pkg/templates/gitlab/factory.gitlab-ci.yml" .factory/ci/factory.gitlab-ci.yml "$prefix" "$ci_mode" --package
touch .gitignore
for line in "instrument/results/" ".env.factory" ".pi-subagents/"; do
  grep -qxF "$line" .gitignore || { printf '%s\n' "$line" >> .gitignore; note ".gitignore += $line"; }
done
touch AGENTS.md
if ! grep -q 'docs/agents/factory.md' AGENTS.md; then
  { echo; sed '/^<!--/,/-->$/d' "$pkg/AGENTS.factory.md"; } >> AGENTS.md; note "AGENTS.md += pointer to docs/agents/factory.md"
fi
if [ -n "$prefix" ] && ! grep -q '^## Monorepo project' AGENTS.md; then
  printf '\n## Monorepo project\n\nThis project is the folder `%s` of a larger git repository. Wherever an instruction or a skill says "repo root" or "project root", it means this folder, not the git root: create `GLOSSARY.md`, `docs/`, `.scratch/` and any new file under it, and never change files outside it.\n' "$prefix" >> AGENTS.md
  note "AGENTS.md += monorepo project note (repo root = $prefix)"
fi

bash "$here/link.sh" | sed 's/^/  /'
if [ ! -f .factory/health-baseline.json ]; then
  bash scripts/factory/health.sh baseline >/dev/null 2>&1 && note "+ .factory/health-baseline.json (ratchet starts from today's code)" || true
fi
if node "$here/effective-models.mjs" | awk -F'\t' '$2 ~ /[<>]/ || $2 == "" { bad = 1 } END { exit bad ? 0 : 1 }'; then
  note "models: placeholders on this machine. Once per machine: node $here/models-profile.mjs apply --user"
fi

cat <<MSG

Nothing committed$( [ "$migrate" -eq 1 ] && printf ' (the removals of the copied files are staged)'). Review, commit on its own branch, MR (D48):
$(git status --short -- . | sed 's/^/  /')
Then: .factory/commands.env (FACTORY_TEST_CMD), the CI variable FACTORY_PACKAGE_GIT
(the URL your CI may fetch pi-factory from, no default), the CI include
  include: [{ local: ${prefix:+$prefix/}.factory/ci/factory.gitlab-ci.yml }]
and, in Pi from here: scripts/factory/doctor.sh.
MSG
