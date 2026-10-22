#!/usr/bin/env bash
# Finds the patch a worker left when the build wave's result didn't return
# it (D39). Looks for *.patch / *.diff files written after the wave's
# workflow file, whose path or neighbouring manifest names the ticket.
# Then falls back to the worker's worktree: pi-subagents keeps one per run
# on a branch named pi-subagents/<ticket>-…, and rebuilds the patch from
# the newest one created after the wave (D60). What the worktree hook added
# (dependency links, .env.factory) is left out of that patch (D65).
# Last, the draft the worker's own self-check saved (D73), which survives
# the worktree's removal.
#
# Usage: scripts/factory/locate-patch.sh <feature> <ticket>
# Prints the patch path, or exits 1 (then: record-no-patch.sh).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: locate-patch.sh <feature> <ticket>}"
require_mission "$feature"
ticket="${2:?usage: locate-patch.sh <feature> <ticket>}"
since="$(ls -t "$(mission_dir "$feature")"/workflows/*-build-wave*.js 2>/dev/null | awk 'NR == 1' || true)"
[ -n "$since" ] || die "no build-wave workflow for $feature yet"

roots=(.pi-subagents "${TMPDIR:-/tmp}" /tmp)
# A patch in a shared temp folder counts only if its run names this checkout:
# two repos (or two test runs) with the same mission name must not pick up
# each other's patches.
top="$(git rev-parse --show-toplevel)"
# pi-subagents keeps a run's patches in <run>/worktree-diffs/step-N/ and its
# manifest (with repoRoot) at the run's top: look up to two folders above.
run_json() { local d; d="$(dirname "$1")"; printf '%s\n' "$d"/*.json "$(dirname "$d")"/*.json "$(dirname "$(dirname "$d")")"/*.json; }
names() { local f; while IFS= read -r f; do [ -f "$f" ] && grep -qsF "$2" "$f" && return 0; done < <(run_json "$1"); return 1; }
ours() { [[ "$1" == .pi-subagents/* ]] || names "$1" "$top"; }
[ -d /var/folders ] && roots+=(/var/folders)
found=""
for root in "${roots[@]}"; do
  [ -d "$root" ] || continue
  while IFS= read -r p; do
    [ -s "$p" ] || continue
    if { [[ "$p" == *"$ticket"* ]] || names "$p" "$ticket"; } && ours "$p"; then
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
    out="$(dirname "$(draft_patch "$feature" "$ticket")")/$ticket.located.patch"; mkdir -p "$(dirname "$out")"
    load_commands
    skip=(); while IFS= read -r x; do skip+=("$x"); done < <(hook_excludes)
    git -C "$wt" add -A -- . "${skip[@]}"
    git -C "$wt" diff --cached --binary "$base" > "$out"
    [ -s "$out" ] && found="$out"
  fi
fi
if [ -z "$found" ]; then
  draft="$(draft_patch "$feature" "$ticket")"
  [ -s "$draft" ] && [ "$draft" -nt "$since" ] && found="$draft"
fi
[ -n "$found" ] || { echo "no patch found for $ticket after $(basename "$since")" >&2; exit 1; }
echo "$found"
