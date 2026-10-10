#!/usr/bin/env bash
# A worker run that ends without a patch is a failed round (D38), exactly
# like a failed integration: it is recorded, it counts toward escalation,
# and the next build of that ticket sees why.
#
# Usage: scripts/factory/record-no-patch.sh <feature> <ticket> [note]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: record-no-patch.sh <feature> <ticket> [note]}"
ticket="${2:?usage: record-no-patch.sh <feature> <ticket> [note]}"
note="${3:-the run ended without changing any file}"
dir="$(mission_dir "$feature")"
[ -f "$dir/issues/$ticket.md" ] || die "unknown ticket $ticket in $dir/issues"

write_fail_verdict "$feature" "$ticket" worker-no-patch \
  "The worker produced no patch ($note). Next round: implement the ticket; if it is too big for one run, say so in your report."
bash "$here/checkpoint.sh" "$feature" >/dev/null
v="$dir/verdicts/$ticket-code.md"
echo "Recorded: $ticket failed round $(verdict_round "$v") (no patch). Run next.sh $feature."
