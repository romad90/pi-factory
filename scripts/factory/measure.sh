#!/usr/bin/env bash
# The measurements an architect reasons from, computed by scripts, no model
# (P22, the architect step). Written to .scratch/<job>/measures.md with ids
# ([M-n]) the strategy must cite.
#
# Usage: scripts/factory/measure.sh <job>
#
# What it measures, in this project folder:
#   tests      the test command's result, its summary lines and duration
#   history    the first commit and the commits of the past year
#   files      per source file the health check flags (deep, large, duplicated)
#              or the past year changed: those flags, its changes in a year,
#              how many files import it, and its mutation score when a mutation
#              report exists (FACTORY_MUTATION_REPORT, default
#              reports/mutation/mutation.json; Stryker's JSON format)
#   surface    a committed public API report (etc/*.api.md), or none
#   missions   the missions already in .scratch/, their intent and outcome
# Mutation testing is not run here (minutes per file): the score is read from
# the last report, with its date, and named as missing when there is none.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

job="${1:?usage: measure.sh <job>}"
dir="$(mission_dir "$job")"
[ -f "$dir/job.md" ] || die "no job at $dir/job.md (start one with: scripts/factory/human.sh job $job \"<what you want>\")"
load_commands
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

rc=-1; secs=0
if [ -n "${FACTORY_TEST_CMD:-}" ]; then
  start="$(date +%s)"
  bash -c "$FACTORY_TEST_CMD" > "$tmp/tests.log" 2>&1 && rc=0 || rc=$?
  secs=$(( $(date +%s) - start ))
fi
bash "$here/health.sh" details > "$tmp/health.txt" 2>/dev/null || true
git log --relative --since="1 year ago" --name-only --format= -- . > "$tmp/churn.txt" 2>/dev/null || true
first="$(git log --reverse --format=%ad --date=short -- . 2>/dev/null | sed -n '1p')"
year="$(git log --since="1 year ago" --format=%h -- . 2>/dev/null | grep -c . || true)"
git ls-files > "$tmp/files.txt"

node "$here/measure.mjs" "$dir/measures.md" "$job" "$tmp" "$rc" "$secs" "${FACTORY_TEST_CMD:-}" \
  "${FACTORY_MUTATION_REPORT:-reports/mutation/mutation.json}" "${first:-}" "${year:-0}" "$FACTORY_DIR"
bash "$here/checkpoint.sh" "$job" >/dev/null
echo "measures: $dir/measures.md ($(grep -c '^| M-' "$dir/measures.md") rows)"
