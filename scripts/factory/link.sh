#!/usr/bin/env bash
# Links this project to the factory installed once on this machine (P11, D92).
# Each path in package-links.txt becomes an untracked link to the package,
# added to .git/info/exclude: the project's history never holds factory code,
# and worker worktrees get the same links (worktree-hook.mjs). Safe to re-run;
# after moving or upgrading the package it points the links at the new place.
#
# Usage, from the project folder (a monorepo project: its own folder):
#   <package>/scripts/factory/link.sh            create or refresh the links
#   <package>/scripts/factory/link.sh --check    exit 1 if a link is missing or points elsewhere
set -euo pipefail
here="$(cd -P "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

mode="${1:-link}"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not in a git repository"
[ "$(cd -P . && pwd)" != "$FACTORY_PACKAGE_ROOT" ] || die "this is the factory itself: run from a project"
prefix="$(git rev-parse --show-prefix)"
exclude="$(git rev-parse --git-common-dir)/info/exclude"
mkdir -p "$(dirname "$exclude")"; touch "$exclude"

bad=0; made=0
while IFS= read -r rel; do
  case "$rel" in ''|'#'*) continue ;; esac
  want="$FACTORY_PACKAGE_ROOT/$rel"
  if [ "$mode" = --check ]; then
    if [ -L "$rel" ] && [ "$(readlink "$rel")" = "$want" ]; then :
    elif [ -e "$rel" ] && [ ! -L "$rel" ]; then :            # copied in (install-into): not a link to check
    else echo "  ✗ $rel: not linked to $want (run: $here/link.sh)"; bad=1; fi
    continue
  fi
  if [ -e "$rel" ] && [ ! -L "$rel" ]; then
    echo "  kept $rel: a copy, not a link (factory onboard --migrate removes the copied factory files)"; continue
  fi
  mkdir -p "$(dirname "$rel")"
  ln -sfn "$want" "$rel"; made=$((made + 1))
  line="/${prefix}${rel}"
  grep -qxF "$line" "$exclude" || printf '%s\n' "$line" >> "$exclude"
done < "$here/package-links.txt"

if [ "$mode" = --check ]; then
  [ "$bad" -eq 0 ] && echo "  ✓ links to the factory package ($FACTORY_PACKAGE_ROOT)"
  exit "$bad"
fi
echo "linked $made path(s) to $FACTORY_PACKAGE_ROOT (untracked, listed in $exclude)"
