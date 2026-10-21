#!/usr/bin/env bash
# A worker's notes for the next round (D84): what it tried, what it ruled
# out and why, where it stopped. Run from the worker's worktree; the text
# goes next to the draft patch in the git folder all worktrees share, and
# integration (pass or fail) moves it into .scratch/<mission>/journal/.
#
# Usage: scripts/factory/journal.sh <feature> <<'FACTORY_TEXT_END'
#        <three to ten lines>
#        FACTORY_TEXT_END
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: journal.sh <feature> < notes}"
ticket="$(worker_ticket "$feature")" || die "run it from your worktree (a pi-subagents/<ticket>-… branch)"
f="$(draft_patch "$feature" "$ticket").journal"
mkdir -p "$(dirname "$f")"
text="$(cat)"
[ -n "$(printf '%s' "$text" | tr -d '[:space:]')" ] || die "empty journal"
printf '%s\n' "$text" > "$f"
echo "Journal saved for $ticket ($(printf '%s\n' "$text" | wc -l | tr -d ' ') lines). The next round reads it."
