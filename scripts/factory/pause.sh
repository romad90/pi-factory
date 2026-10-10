#!/usr/bin/env bash
# Pause and pick up a mission (D45). State already lives in files; this adds
# what a new session needs to continue: where it stopped, open questions,
# and why it paused. /factory resumes from it in a fresh session.
#
# Usage: scripts/factory/pause.sh <feature> [reason]
#        scripts/factory/pause.sh resume <feature>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

if [ "${1:-}" = "resume" ]; then
  feature="${2:?usage: pause.sh resume <feature>}"; p="$(mission_dir "$feature")/state/PAUSED.md"
  [ -f "$p" ] || { echo "Not paused."; exit 0; }
  cat "$p"; rm -f "$p"
  bash "$here/checkpoint.sh" "$feature" >/dev/null
  echo; echo "Resumed. Continue with: scripts/factory/next.sh $feature"
  exit 0
fi

feature="${1:?usage: pause.sh <feature> [reason] | pause.sh resume <feature>}"; shift
dir="$(mission_dir "$feature")"; [ -d "$dir" ] || die "no mission at $dir"
mkdir -p "$dir/state"; p="$dir/state/PAUSED.md"
{
  printf '# Paused: %s\n**When:** %s\n**HEAD:** %s\n**Reason:** %s\n\n' \
    "$feature" "$(date '+%F %H:%M')" "$(git rev-parse --short HEAD)" "${*:-not given}"
  echo '## Where it stopped'; echo '```'
  FACTORY_NOTIFY=0 bash "$here/next.sh" "$feature" 2>&1 || true
  echo '```'
  if [ -f "$dir/state/open-question.md" ]; then echo; echo '## Open question'; cat "$dir/state/open-question.md"; fi
} > "$p"
bash "$here/checkpoint.sh" "$feature" >/dev/null
echo "Paused. Start a new session and run: /factory $feature"
