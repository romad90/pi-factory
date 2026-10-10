#!/usr/bin/env bash
# Run by the lead after every review, validation or light review wave.
# Turns what the agents wrote into the record the gates trust:
#   - each new verdict becomes the next round of its history (D38)
#   - **Model:** is the agent's configured model, not its own guess (D39)
#   - assertion and quality-bar lines are counted as PASS-with-evidence / FAIL / UNVERIFIED (D40)
# Then checkpoints the mission.
#
# Usage: scripts/factory/collect.sh <feature>
#        scripts/factory/collect.sh --light <slug>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

summary() {                            # <file>
  local p f u r
  read -r p f u < <(verdict_evidence_counts "$1")
  r="$(verdict_field "$1" Result)"
  printf '  %-40s %-5s round %-2s assertions: %s pass, %s fail, %s unverified\n' \
    "$(basename "$1")" "${r:-?}" "$(verdict_round "$1")" "$p" "$f" "$u"
  if [ "$r" = "PASS" ] && [ "$u" -gt 0 ]; then
    echo "      ! PASS with unverified assertions: $(verdict_unverified_ids "$1" | paste -sd' ' -)"
  fi
}

if [ "${1:-}" = "--light" ]; then
  slug="${2:?usage: collect.sh --light <slug>}"
  v="$FACTORY_DIR/light/$slug/verdicts/code.md"
  [ -f "$v" ] || die "no light verdict at $v"
  record_verdict "$v" factory-reviewer
  echo "Light review $slug"; summary "$v"
  bash "$here/checkpoint.sh" --light "$slug" >/dev/null
  exit 0
fi

feature="${1:?usage: collect.sh <feature> | --light <slug>}"
dir="$(mission_dir "$feature")"
[ -d "$dir/verdicts" ] || die "no verdicts in $dir yet"
echo "Verdicts: $feature"
shopt -s nullglob
for v in "$dir"/verdicts/*-code.md; do
  record_verdict "$v" factory-reviewer; summary "$v"
done
if [ -f "$dir/verdicts/behavior.md" ]; then
  record_verdict "$dir/verdicts/behavior.md" factory-validator; summary "$dir/verdicts/behavior.md"
fi
if [ -f "$dir/verdicts/health.md" ]; then
  record_verdict "$dir/verdicts/health.md" factory-code-steward; summary "$dir/verdicts/health.md"
fi
bash "$here/checkpoint.sh" "$feature" >/dev/null
