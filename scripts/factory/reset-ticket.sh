#!/usr/bin/env bash
# Puts a ticket back to "never built" (D63): removes its code verdict, the
# verdict's round copies (.rN) and its integration marker, logs the reset in
# decisions.tsv and commits, so next.sh rebuilds it from round 1. Code
# already integrated stays in git: revert it first if it must go.
#
# --review (F4, D118): the ticket's integrated code stands and only its
# review must run again (a contract amended after the review, a FAIL no patch
# can change). The verdict is set aside in state/, its round copies kept as
# history, an open question about the ticket closed; next.sh then sends the
# ticket to review, not to build. Refused for a ticket that isn't integrated.
#
# Usage: scripts/factory/reset-ticket.sh <mission> <ticket> [reason]
#        scripts/factory/reset-ticket.sh <mission> <ticket> --review "<why>"
#        scripts/factory/reset-ticket.sh <mission> <ticket> --review --stdin < why
# --stdin reads the reason verbatim, newlines become spaces (as human.sh does).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

usage="usage: reset-ticket.sh <mission> <ticket> [reason] | <mission> <ticket> --review \"<why>\""
feature="${1:?$usage}"
require_mission "$feature"
ticket="${2:?$usage}"
ticket="${ticket%.md}"
dir="$(mission_dir "$feature")"
[ -f "$dir/issues/$ticket.md" ] || die "unknown ticket $ticket in $dir/issues"
shopt -s nullglob

if [ "${3:-}" = "--review" ]; then
  if [ "${4:-}" = --stdin ]; then why="$(tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"; else why="${4:-}"; fi
  [ -n "$why" ] || die "--review needs a reason: what changed since the review"
  [ -n "$(ticket_marker "$feature" "$ticket")" ] || die "$ticket isn't integrated: there is nothing to review again (reset-ticket.sh $feature $ticket rebuilds it)"
  v="$dir/verdicts/$ticket-code.md"
  [ -f "$v" ] || { echo "No verdict for $ticket: next.sh already sends it to review."; exit 0; }
  mkdir -p "$dir/state"
  if git ls-files --error-unmatch -- "$v" >/dev/null 2>&1; then git mv -f -- "$v" "$dir/state/$ticket.superseded-verdict.md"; else mv -f -- "$v" "$dir/state/$ticket.superseded-verdict.md"; fi
  rm -f "$dir/state/$ticket.stuck" "$dir/state/$ticket.not-run" "$dir/state/$ticket.sent-back"
  q="$dir/state/open-question.md"
  if [ -f "$q" ] && grep -q "^\*\*Ticket:\*\* $ticket\$" "$q"; then
    if git ls-files --error-unmatch -- "$q" >/dev/null 2>&1; then git rm -q -- "$q"; else rm -f -- "$q"; fi
  fi
  decision_log "$feature" "$ticket" rereview "review the integrated ticket again, no rebuild" "$why"
  git add -A -- "$dir"
  git commit -q -m "chore($feature): review $ticket again" -m "Factory-Script: reset-ticket" -- "$dir"
  echo "$ticket goes back to review, its integration kept: $(git rev-parse --short HEAD). The old verdict is in state/$ticket.superseded-verdict.md."
  exit 0
fi

files=("$dir/verdicts/$ticket-code.md" "$dir/verdicts/$ticket-code".r*.md "$dir/state/$ticket.integrated"
       "$dir/state/$ticket.stuck" "$dir/state/$ticket.signature" "$dir/state/$ticket.stale-verdict.md")
removed=0
for f in "${files[@]}"; do
  [ -e "$f" ] || continue
  if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then git rm -q -- "$f"; else rm -f -- "$f"; fi
  echo "  - removed $f"; removed=$((removed + 1))
done
[ "$removed" -gt 0 ] || { echo "Nothing to reset for $ticket."; exit 0; }

decision_log "$feature" "$ticket" reset "reset the ticket to round 1" "${3:-reset by hand}"
git add -- "$dir"
git commit -q -m "chore($feature): reset $ticket" -m "Factory-Script: reset-ticket" -- "$dir"
echo "Reset $ticket ($removed files): $(git rev-parse --short HEAD). Next build starts at round 1."
