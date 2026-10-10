#!/usr/bin/env bash
# Finds the patch a worker left when the build wave's result didn't return
# it (D39). Looks for *.patch / *.diff files written after the wave's
# workflow file, whose path or neighbouring manifest names the ticket.
#
# Usage: scripts/factory/locate-patch.sh <feature> <ticket>
# Prints the patch path, or exits 1 (then: record-no-patch.sh).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: locate-patch.sh <feature> <ticket>}"
ticket="${2:?usage: locate-patch.sh <feature> <ticket>}"
since="$(ls -t "$(mission_dir "$feature")"/workflows/*-build-wave*.js 2>/dev/null | head -1 || true)"
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
  done < <(find "$root" -maxdepth 6 -type f \( -name '*.patch' -o -name '*.diff' \) -newer "$since" 2>/dev/null)
done
[ -n "$found" ] || { echo "no patch found for $ticket after $(basename "$since")" >&2; exit 1; }
echo "$found"
