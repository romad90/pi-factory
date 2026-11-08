#!/usr/bin/env bash
# factory learn-loop <project-dir>...: the learning loop's evidence (P26), from
# raw records. For each project: copies the lead's Pi sessions into
# .git/pi-factory/lead-sessions (the archive keeps only the agents'), writes
# events.tsv and calls.json under the private data folder, and replays every
# recorded guard refusal through the current guard. Read-only for the
# projects' code; writes only under .git/pi-factory/ and the data folder.
# Then the lessons from other machines (P27, D115): every *.lesson.json in the
# data folder's inbox/ (factory learn-export writes them there, elsewhere) is
# checked word by word, replayed through this guard, and summed up in
# lessons/<date>/: lessons.tsv, causes.tsv, and fixtures.json for the shapes
# this guard still refuses. With no project and lessons in the inbox, only that.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
sessions="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/sessions"
data="${FACTORY_DATA_DIR:-$HOME/.pi-factory/data}"
inbox="$data/inbox"
has_lessons() { compgen -G "$inbox/*.lesson.json" >/dev/null; }
[ $# -gt 0 ] || has_lessons || { echo "usage: factory learn-loop <project-dir>... (or lessons in $inbox)" >&2; exit 2; }
day="$(date +%F)"
for p in "$@"; do
  p="$(cd "$p" && pwd -P)"
  [ -d "$p/.git" ] || { echo "skip $p: not a git checkout" >&2; continue; }
  slug="--$(printf '%s' "$p" | sed 's|^/||; s|/|-|g')--"
  mkdir -p "$p/.git/pi-factory/lead-sessions"
  if [ -d "$sessions/$slug" ]; then cp -p "$sessions/$slug"/*.jsonl "$p/.git/pi-factory/lead-sessions/" 2>/dev/null || true; fi
  out="$data/$(basename "$p")/learn/$day"
  echo "== $(basename "$p")"
  node "$here/learn-records.mjs" events "$p" "$out"
  node "$here/learn-records.mjs" replay "$out"
done
if has_lessons; then
  echo "== lessons from elsewhere ($inbox)"
  node "$here/learn-export.mjs" ingest "$inbox" "$data/lessons/$day"
fi
