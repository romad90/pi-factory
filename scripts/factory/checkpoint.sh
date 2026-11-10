#!/usr/bin/env bash
# Commits a mission's state (spec, tickets, verdicts, logs, decisions) so
# worker worktrees, which branch from HEAD, can read it. Mission files never
# make a verdict stale (D10), so checkpointing is always safe. The factory's
# scripts call it themselves after every change they make (D46); you rarely
# need to run it by hand.
#
# Usage: scripts/factory/checkpoint.sh <feature>
#        scripts/factory/checkpoint.sh --light <slug>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

if [ "${1:-}" = "--light" ]; then
  name="${2:?usage: checkpoint.sh --light <slug>}"; dir="$FACTORY_DIR/light/$name"
else
  name="${1:?usage: checkpoint.sh <feature> | --light <slug>}"; dir="$(mission_dir "$name")"
fi
[ -d "$dir" ] || die "nothing at $dir"
why="$(reattach_head)" || die "$why"
# B0: a judge's copy of the project (git archive + npm ci), a node_modules or
# an npm cache is never mission state, wherever it sits under the mission
# folder: one such copy made 4,880 of a PR's files and broke Windows checkout.
# A copy is a folder below the mission root holding a project manifest or a
# .git; the evidence files beside it (*.md, *.json, *.tap, *.diff, lcov.info)
# still go in.
skip=()
while IFS= read -r -d '' p; do skip+=("$p"); done < <(
  find "$dir" -mindepth 1 -type d \( -name node_modules -o -name _cacache -o -name .npm -o -name npm-cache -o -name .npm-cache \
    -o -exec sh -c 'for f in package.json .git go.mod Cargo.toml pyproject.toml pom.xml build.gradle; do [ -e "$1/$f" ] && exit 0; done; exit 1' _ {} \; \) \
    -prune -print0 2>/dev/null)
# The commit is built in an index of its own, from HEAD: `git commit -- <dir>`
# would take a copy an older checkpoint committed back from the disk, and
# changes someone staged outside the mission stay staged and uncommitted.
idx="$(mktemp)"; trap 'rm -f "$idx"' EXIT
GIT_INDEX_FILE="$idx" git read-tree HEAD
excl=()
for p in ${skip[@]+"${skip[@]}"}; do
  [ -z "$(GIT_INDEX_FILE="$idx" git ls-files -- ":(literal)$p" | head -1)" ] || GIT_INDEX_FILE="$idx" git rm -r -q --cached -- ":(literal)$p"
  ! git check-ignore -q -- "$p" || continue
  excl+=(":(exclude,literal)$p")
  echo "Copy left out of the mission state: $p (keep copies under $FACTORY_DIR/<mission>/tmp/copies/)"
done
GIT_INDEX_FILE="$idx" git add -A -- "$dir" ${excl[@]+"${excl[@]}"}
if GIT_INDEX_FILE="$idx" git diff --cached --quiet; then
  echo "State already committed."
else
  GIT_INDEX_FILE="$idx" git commit -q --author="$FACTORY_AUTHOR" -m "chore(factory): $name state" -m "Factory-Script: checkpoint"
  git reset -q -- "$dir"
  echo "Committed state: $(git rev-parse --short HEAD)"
fi
