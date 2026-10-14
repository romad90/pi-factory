#!/usr/bin/env bash
# Puts a ticket back to "never built" (D63): removes its code verdict, the
# verdict's round copies (.rN) and its integration marker, logs the reset in
# decisions.tsv and commits, so next.sh rebuilds it from round 1. Code
# already integrated stays in git: revert it first if it must go.
#
# Usage: scripts/factory/reset-ticket.sh <mission> <ticket> [reason]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: reset-ticket.sh <mission> <ticket> [reason]}"
ticket="${2:?usage: reset-ticket.sh <mission> <ticket> [reason]}"
ticket="${ticket%.md}"
dir="$(mission_dir "$feature")"
[ -f "$dir/issues/$ticket.md" ] || die "unknown ticket $ticket in $dir/issues"

shopt -s nullglob
files=("$dir/verdicts/$ticket-code.md" "$dir/verdicts/$ticket-code".r*.md "$dir/state/$ticket.integrated")
removed=0
for f in "${files[@]}"; do
  [ -e "$f" ] || continue
  if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then git rm -q -- "$f"; else rm -f -- "$f"; fi
  echo "  - removed $f"; removed=$((removed + 1))
done
[ "$removed" -gt 0 ] || { echo "Nothing to reset for $ticket."; exit 0; }

decision_log "$feature" "$ticket" reset "reset the ticket to round 1" "${3:-reset by hand}"
git add -- "$dir"
git commit -q -m "chore($feature): reset $ticket" -- "$dir"
echo "Reset $ticket ($removed files): $(git rev-parse --short HEAD). Next build starts at round 1."
