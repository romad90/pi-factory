#!/usr/bin/env bash
# Finds the patch a worker left when the build wave's result didn't return
# it (D39). Looks for *.patch / *.diff files written after the wave's
# workflow file, whose path or neighbouring manifest names the ticket.
# Then falls back to the worker's worktree: pi-subagents keeps one per run
# on a branch named pi-subagents/<ticket>-…, and rebuilds the patch from
# the newest one created after the wave (D60).
#
# Usage: scripts/factory/locate-patch.sh <feature> <ticket>
# Prints the patch path, or exits 1 (then: record-no-patch.sh).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: locate-patch.sh <feature> <ticket>}"
ticket="${2:?usage: locate-patch.sh <feature> <ticket>}"
since="$(ls -t "$(mission_dir "$feature")"/workflows/*-build-wave*.js 2>/dev/null | awk 'NR == 1' || true)"
[ -n "$since" ] || die "no build-wave workflow for $feature yet"

roots=(.pi-subagents "${TMPDIR:-/tmp}" /tmp)
[ -d /var/folders ] && roots+=(/var/folders)
found=""
for root in "${roots[@]}"; do
  [ -d "$root" ] || continue
  while IFS= read -r p; do
    [ -s "$p" ] || continue
    if [[ "$p" == *"$ticket"* ]] || grep -qsF "$ticket" "$(dirname "$p")"/*.json 2>/dev/null; then
      found="$p"; break 2
    fi
  done < <(find "$root" -maxdepth 10 -type f \( -name '*.patch' -o -name '*.diff' \) -newer "$since" 2>/dev/null)
done
if [ -z "$found" ]; then
  wt=""
  while IFS=$'\t' read -r path branch; do
    [[ "$branch" == refs/heads/pi-subagents/"$ticket"-* ]] || continue
    [ -d "$path" ] && [ -n "$(find "$path" -maxdepth 0 -newer "$since" 2>/dev/null)" ] || continue
    [ -z "$wt" ] || [ "$path" -nt "$wt" ] && wt="$path"
  done < <(git worktree list --porcelain | awk '/^worktree /{p=substr($0,10)} /^branch /{print p "\t" $2}')
  if [ -n "$wt" ]; then
    base="$(git merge-base "$(git -C "$wt" rev-parse HEAD)" HEAD)"
    out="${TMPDIR:-/tmp}/pi-factory-$feature-$ticket.patch"
    git -C "$wt" add -A
    git -C "$wt" diff --cached --binary "$base" > "$out"
    [ -s "$out" ] && found="$out"
  fi
fi
[ -n "$found" ] || { echo "no patch found for $ticket after $(basename "$since")" >&2; exit 1; }
echo "$found"
