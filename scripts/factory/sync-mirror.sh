#!/usr/bin/env bash
# Bring a released factory version into an internal mirror, then into the
# projects that use it: the whole upgrade in one command, nothing copied by hand.
#
# Usage (from anywhere):
#   <clone>/scripts/factory/sync-mirror.sh <mirror-repo> [--dir pi-factory] [--version vX] [--push] [--projects]
#
# 1. Updates this clone (the one the script lives in): switches to develop and
#    pulls (fast-forward only), so a detached HEAD left by a tag checkout is fine.
# 2. Picks the latest release tag on develop, or --version.
# 3. Replaces <mirror-repo>/<dir> with exactly that version's tracked files
#    (git archive: no .git, files the version deleted are gone), refusing when
#    the folder has local changes, and commits "chore: pi-factory <version>".
#    --push pushes the mirror's current branch.
# 4. --projects: for each project listed in ~/.pi-factory/projects (one path
#    per line), when its tree is clean: factory onboard --no-setup, then commit
#    .factory/VERSION and .factory/package-sha on its current branch. A project
#    with local changes is skipped and named; onboard's other changes are left
#    for you to review.
set -euo pipefail
die() { printf 'sync-mirror: %s\n' "$*" >&2; exit 1; }
src="$(cd "$(dirname "$0")/../.." && pwd)"
mirror=""; sub="pi-factory"; want=""; push=""; projects=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) sub="${2:?--dir needs a folder}"; shift 2 ;;
    --version) want="${2:?--version needs a tag}"; shift 2 ;;
    --push) push=1; shift ;;
    --projects) projects=1; shift ;;
    -*) die "unknown option $1" ;;
    *) mirror="$1"; shift ;;
  esac
done
[ -n "$mirror" ] || die "usage: sync-mirror.sh <mirror-repo> [--dir pi-factory] [--version vX] [--push] [--projects]"
mirror="$(cd "$mirror" && git rev-parse --show-toplevel)" || die "$mirror is not a git repository"
[ "$mirror" != "$src" ] || die "the mirror can't be this clone"
case "$sub" in /*|*..*|"") die "--dir must be a folder inside the mirror" ;; esac

# 1. This clone, up to date.
[ -z "$(git -C "$src" status --porcelain)" ] || die "$src has local changes: it is the source, keep it clean"
git -C "$src" fetch -q --tags origin
git -C "$src" switch -q develop 2>/dev/null || git -C "$src" switch -q -c develop --track origin/develop
git -C "$src" pull -q --ff-only origin develop

# 2. The version.
v="${want:-$(git -C "$src" describe --tags --abbrev=0 HEAD)}"
git -C "$src" rev-parse -q --verify "$v^{commit}" >/dev/null || die "no version $v in $src"

# 3. The mirror.
dst="$mirror/$sub"
[ ! -e "$dst/.git" ] || die "$dst holds a .git (a copied clone?): remove it first (rm -rf $dst/.git), then rerun"
[ -z "$(git -C "$mirror" status --porcelain -- "$sub")" ] || die "$dst has local changes: commit or discard them first (git -C $mirror status -- $sub)"
have="$(cat "$dst/.factory/VERSION" 2>/dev/null || true)"
rm -rf "$dst"
git -C "$src" archive --prefix="$sub/" "$v" | tar -x -C "$mirror"
git -C "$mirror" add -A -- "$sub"
if git -C "$mirror" diff --cached --quiet -- "$sub"; then
  echo "mirror: $sub already at $v"
else
  git -C "$mirror" commit -q -m "chore: pi-factory $v" -- "$sub"
  echo "mirror: $sub ${have:+$have → }$v, committed on $(git -C "$mirror" branch --show-current)"
fi
if [ -n "$push" ]; then git -C "$mirror" push -q && echo "mirror: pushed"; fi

# 4. The projects.
[ -n "$projects" ] || { echo "projects: run factory onboard --no-setup in each (or rerun with --projects)"; exit 0; }
list="$HOME/.pi-factory/projects"
[ -f "$list" ] || { echo "projects: no $list (one project path per line)"; exit 0; }
while IFS= read -r p; do
  p="${p/#\~/$HOME}"; [ -n "$p" ] && [ "${p#\#}" = "$p" ] || continue
  [ -d "$p" ] || { echo "  $p: missing, skipped"; continue; }
  if [ -n "$(git -C "$p" status --porcelain --untracked-files=no)" ]; then echo "  $p: local changes, skipped"; continue; fi
  ( cd "$p" && bash "$dst/scripts/factory/onboard.sh" --no-setup >/dev/null 2>&1 ) || { echo "  $p: onboard failed (run it there to see why)"; continue; }
  git -C "$p" add -- .factory/VERSION .factory/package-sha 2>/dev/null || true
  if git -C "$p" diff --cached --quiet; then echo "  $p: already at $v"
  else git -C "$p" commit -q -m "chore: pi-factory $v" && echo "  $p: $v, committed on $(git -C "$p" branch --show-current)"; fi
  rest="$(git -C "$p" status --porcelain | grep -c . || true)"
  [ "$rest" -eq 0 ] || echo "    and $rest other file(s) onboard changed: review them (git -C $p status)"
done < "$list"
