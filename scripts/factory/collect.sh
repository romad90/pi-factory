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
  # D69: a new verdict without a PASS/FAIL Result line is the reviewer's
  # format slip, not a finding. Sent back to review once instead of counting
  # as a failed round; a second slip on the same ticket counts.
  ticket="$(basename "$v" -code.md)"; sent="$dir/state/$ticket.sent-back"
  n="$(verdict_history_count "$v")"
  if [ -n "$(ticket_marker "$feature" "$ticket")" ] && ! [[ "$(verdict_field "$v" Result)" =~ ^(PASS|FAIL)$ ]] \
     && { [ "$n" -eq 0 ] || ! cmp -s "$v" "${v%.md}.r$n.md"; } && [ ! -f "$sent" ]; then
    mkdir -p "$dir/state"; mv "$v" "$dir/state/$ticket.invalid-verdict.md"; echo "$n" > "$sent"
    printf '  %-40s sent back to review: no **Result:** PASS or FAIL line (kept in state/%s.invalid-verdict.md)\n' "$(basename "$v")" "$ticket"
    continue
  fi
  # D81: a review of an older commit than the ticket's last integration is
  # stale (a late verdict, a reviewer handed the wrong commit). It is kept
  # aside, never counted as a round, and the ticket goes back to review.
  marker="$(ticket_marker "$feature" "$ticket")"; vc="$(verdict_field "$v" Commit)"
  if [ -n "$marker" ] && [ -n "$vc" ] && [ "$vc" != "$marker" ] \
     && ! [[ "$(verdict_field "$v" Brief)" =~ ^(integrate|worker-no-patch|patch-guard)$ ]] \
     && { [ "$n" -eq 0 ] || ! cmp -s "$v" "${v%.md}.r$n.md"; }; then
    mkdir -p "$dir/state"; mv "$v" "$dir/state/$ticket.stale-verdict.md"
    if [ "$n" -gt 0 ]; then cp "${v%.md}.r$n.md" "$v"; fi
    printf '  %-40s stale: reviews %s, the ticket is integrated at %s; sent back to review (kept in state/%s.stale-verdict.md)\n' \
      "$(basename "$v")" "${vc:0:8}" "${marker:0:8}" "$ticket"
    continue
  fi
  record_verdict "$v" factory-reviewer; summary "$v"
  [[ "$(verdict_field "$v" Result)" =~ ^(PASS|FAIL)$ ]] && rm -f "$sent" "$dir/state/$ticket.invalid-verdict.md"
done
if [ -f "$dir/verdicts/behavior.md" ]; then
  record_verdict "$dir/verdicts/behavior.md" factory-validator; summary "$dir/verdicts/behavior.md"
fi
if [ -f "$dir/verdicts/health.md" ]; then
  record_verdict "$dir/verdicts/health.md" factory-code-steward; summary "$dir/verdicts/health.md"
fi
bash "$here/usage.sh" "$feature" >/dev/null 2>&1 || true   # D85
bash "$here/archive.sh" collect "$feature" >/dev/null 2>&1 || true   # D97
bash "$here/checkpoint.sh" "$feature" >/dev/null
