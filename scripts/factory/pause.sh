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
reason="${*:-not given}"
# When the provider says when its limit resets ("Limit resets at: 2026-11-06
# 22:28:15 UTC"), that time; else a window named next to "quota" (minute, hour,
# day). Node does the date arithmetic: GNU and BSD date differ (macOS).
after="$(node -e '
const r = process.argv[1], low = r.toLowerCase(), now = Date.now(), pad = (n) => String(n).padStart(2, "0");
const fmt = (t) => { const d = new Date(t); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`; };
const m = r.match(/resets?\s+at:?\s*(\d{4}-\d\d-\d\d[ T]\d\d:\d\d(?::\d\d)?)\s*(utc|z)?/i);
if (m) { const t = Date.parse(m[1].replace(" ", "T") + (m[2] ? "Z" : "")); if (!isNaN(t)) { console.log(fmt(t + 60000)); process.exit(0); } }
const q = /quota|rate.?limit/.test(low);
if (q && /\bday\b|daily/.test(low)) { const d = new Date(now + 86400000); d.setHours(0, 5, 0, 0); console.log(fmt(d)); }
else if (q && /\bhour\b|hourly/.test(low)) console.log(fmt(now + 3600000));
else if (/quota/.test(low) && /\bminute\b/.test(low)) console.log(fmt(now + 300000));
' "$reason" 2>/dev/null || true)"
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
