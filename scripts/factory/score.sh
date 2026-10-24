#!/usr/bin/env bash
# Score archived runs for failure modes tests can't see (D97, P14).
#
# Usage: scripts/factory/score.sh <feature> [--dimension <name>] [--sample <n>]
#   Dimensions: .factory/scoring/<name>.md (what to look for, roles, sample rate).
#   Runs: the mission's run archive (archive.sh collect runs first).
#   Judge: a model of another family than the run's (FACTORY_JUDGE_MODELS, else
#   the factory's judge roles), through FACTORY_JUDGE_CMD (default: pi, judge-pi.sh).
#   Output: .scratch/<feature>/scores.tsv, one line per run × dimension.
# A finding is evidence for a person or for P5, never an automatic change.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

usage="usage: score.sh <feature> [--dimension <name>] [--sample <n>]"
feature="${1:?$usage}"; shift
dim=""; sample=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dimension) dim="${2:?$usage}"; shift ;;
    --sample) sample="${2:?$usage}"; [[ "$sample" =~ ^[0-9]+$ ]] || die "$usage"; shift ;;
    *) die "$usage" ;;
  esac
  shift
done
dir="$(mission_dir "$feature")"
[ -f "$dir/spec.md" ] || die "no mission '$feature'"
bash "$here/archive.sh" collect "$feature" >/dev/null 2>&1 || true
archive="$(dirname "$(dirname "$(dirname "$(draft_patch x x)")")")/archive/$feature"
node "$here/score.mjs" "$archive" .factory/scoring "$dir" "$dir/scores.tsv" "$dim" "$sample"
