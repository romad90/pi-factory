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
  after="$(sed -n 's/^\*\*Resume after:\*\* //p' "$p")"
  if [ -n "$after" ] && [ "$(date '+%F %H:%M')" \< "$after" ] && [ "${FACTORY_RESUME_NOW:-0}" != 1 ]; then
    echo "Still paused: the quota resets at $after; running now fails the same way. (FACTORY_RESUME_NOW=1 to resume anyway)"; exit 1
  fi
  cat "$p"; rm -f "$p"
  bash "$here/checkpoint.sh" "$feature" >/dev/null
  echo; echo "Resumed. Continue with: scripts/factory/next.sh $feature"
  exit 0
fi

feature="${1:?usage: pause.sh <feature> [reason] | pause.sh resume <feature>}"; shift
require_mission "$feature"; dir="$(mission_dir "$feature")"
mkdir -p "$dir/state"; p="$dir/state/PAUSED.md"
# A quota with a time window ("window":"hour", per minute, per day) can't be
# retried before it resets: say when, so nobody burns a run finding out.
reason="${*:-not given}"; after=""
case "$(tr 'A-Z' 'a-z' <<<"$reason")" in
  *quota*day*|*day*quota*|*daily*) after="$(date -d '+1 day' '+%F 00:05' 2>/dev/null || true)" ;;
  *quota*hour*|*hour*quota*|*hourly*) after="$(date -d '+1 hour' '+%F %H:%M' 2>/dev/null || true)" ;;
  *quota*minute*|*minute*quota*) after="$(date -d '+5 minutes' '+%F %H:%M' 2>/dev/null || true)" ;;
esac
{
  printf '# Paused: %s\n**When:** %s\n**HEAD:** %s\n**Reason:** %s\n' \
    "$feature" "$(date '+%F %H:%M')" "$(git rev-parse --short HEAD)" "$reason"
  [ -z "$after" ] || printf '**Resume after:** %s\n' "$after"
  echo
  echo '## Where it stopped'; echo '```'
  FACTORY_NOTIFY=0 bash "$here/next.sh" "$feature" 2>&1 || true
  echo '```'
  if [ -f "$dir/state/open-question.md" ]; then echo; echo '## Open question'; cat "$dir/state/open-question.md"; fi
} > "$p"
bash "$here/checkpoint.sh" "$feature" >/dev/null
echo "Paused${after:+ until $after (a quota window)}. Then start a new session and run: /factory $feature"
