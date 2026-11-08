#!/usr/bin/env bash
# factory learn-export [--source <label>] <project-dir>...: the learning loop's
# evidence from a machine whose records must stay there (P27, D115). Runs
# learn-loop on each project (records stay in its private data folder), then
# writes one lesson file built only from the factory's vocabulary to
# ${FACTORY_DATA_DIR:-~/.pi-factory/data}/outbox/<label>-<date>.lesson.json and
# prints it. Refuses (exit 3, nothing written) if a word outside that
# vocabulary, or on the denylist, would go in. Add your company's words to
# ~/.pi-factory/scrub-terms (one per line) so the denylist knows them too.
# Read the lesson, then put it in the factory machine's
# ~/.pi-factory/data/inbox/: its nightly learn-loop learns from it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source="work"
if [ "${1:-}" = "--source" ]; then source="${2:?--source needs a label}"; shift 2; fi
[ $# -gt 0 ] || { echo "usage: factory learn-export [--source <label>] <project-dir>..." >&2; exit 2; }
data="${FACTORY_DATA_DIR:-$HOME/.pi-factory/data}"
day="$(date +%F)"
pairs=()
for p in "$@"; do
  p="$(cd "$p" && pwd -P)"
  bash "$here/learn-loop.sh" "$p" >/dev/null
  pairs+=("$p" "$data/$(basename "$p")/learn/$day")
done
mkdir -p "$data/outbox"
out="$data/outbox/$source-$day.lesson.json"
node "$here/learn-export.mjs" export "$out" "$source" "${pairs[@]}"
