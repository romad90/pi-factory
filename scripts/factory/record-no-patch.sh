#!/usr/bin/env bash
# A worker run that ends without a patch is a failed round (D38), exactly
# like a failed integration: it is recorded, it counts toward escalation,
# and the next build of that ticket sees why.
#
# Except when the model provider stopped the run (rate limit, quota, 5xx,
# overloaded, timeout): the worker never got to work, so no round is
# recorded. The mission pauses with the error instead, and resumes when the
# provider is back (D58).
#
# Usage: scripts/factory/record-no-patch.sh <feature> <ticket> [note]
#        scripts/factory/record-no-patch.sh <feature> <ticket> --provider "<error line>"
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: record-no-patch.sh <feature> <ticket> [note | --provider <error>]}"
require_mission "$feature"
ticket="${2:?usage: record-no-patch.sh <feature> <ticket> [note | --provider <error>]}"
dir="$(mission_dir "$feature")"
[ -f "$dir/issues/$ticket.md" ] || die "unknown ticket $ticket in $dir/issues"

if [ "${3:-}" = "--provider" ]; then
  err="${4:-provider error, no detail given}"
  bash "$here/pause.sh" "$feature" "provider error on $ticket, no round recorded: $err" >/dev/null
  echo "Not a round: the provider stopped $ticket ($err). Mission paused."
  echo "When the provider is available again (rate limit reset, quota raised), start a new session and run: /factory $feature"
  exit 0
fi

# B1: the worker's self-check found nothing to change. On an integrated
# ticket that is a claim about the code already in: its review runs again on
# that code (reset-ticket.sh --review), no round is spent. Either way a draft
# left from an earlier round goes, so nothing integrates it later.
d="$(draft_patch "$feature" "$ticket")"
if [[ "$(cat "$d.status" 2>/dev/null || true)" == "FAIL change"* ]]; then
  rm -f "$d" "$d.status"
  if [ -n "$(ticket_marker "$feature" "$ticket")" ] && [ -f "$dir/verdicts/$ticket-code.md" ]; then
    bash "$here/reset-ticket.sh" "$feature" "$ticket" --review "the worker found nothing to change: the integrated code goes to review again, no round spent"
    exit 0
  fi
  set -- "$1" "$2" "${3:-the self-check found nothing to change, and nothing of this ticket is integrated}"
fi
note="${3:-the run ended without changing any file}"
write_fail_verdict "$feature" "$ticket" worker-no-patch \
  "The worker produced no patch ($note). Next round: implement the ticket; if it is too big for one run, say so in your report."
bash "$here/checkpoint.sh" "$feature" >/dev/null
v="$dir/verdicts/$ticket-code.md"
echo "Recorded: $ticket failed round $(verdict_round "$v") (no patch). Run next.sh $feature."
