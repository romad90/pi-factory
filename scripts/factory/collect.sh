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
mkdir -p "$dir/verdicts" "$dir/state"
echo "Verdicts: $feature"
shopt -s nullglob
# P25 (1): a verdict is a file, or nothing. A review run can return before its
# file lands (asynchronous runs): wait a little for each reviewed ticket's file,
# then send a ticket that still has none back to review, once; a second run
# without a file escalates it instead of looping.
compute_ticket_state "$feature"
waiting=("${T_REVIEW[@]}")
deadline=$(( $(date +%s) + ${FACTORY_COLLECT_WAIT:-60} ))
while [ ${#waiting[@]} -gt 0 ] && [ "$(date +%s)" -lt "$deadline" ]; do
  left=()
  for t in "${waiting[@]}"; do [ "$(verdict_field "$dir/verdicts/$t-code.md" Commit)" = "$(ticket_marker "$feature" "$t")" ] || left+=("$t"); done
  waiting=("${left[@]}"); [ ${#waiting[@]} -eq 0 ] || sleep 5
done
absdir="$(cd "$dir" && pwd)"
for t in "${waiting[@]}"; do
  [ ! -f "$dir/verdicts/$t-code.md" ] || continue      # an older verdict: the stale check below sends it back
  c="$dir/state/$t.no-verdict"; k=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); echo "$k" > "$c"
  if [ "$k" -ge 2 ]; then
    printf 'two review runs left no verdict file at %s\n' "$absdir/verdicts/$t-code.md" > "$dir/state/$t.stuck"
    printf '  %-40s no verdict file again (%s): escalated, see state/%s.stuck\n' "$t-code.md" "$absdir/verdicts/$t-code.md" "$t"
  else
    printf '  %-40s no verdict file at %s: the review run left none; next.sh sends it back to review\n' "$t-code.md" "$absdir/verdicts/$t-code.md"
  fi
done
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
     && ! [[ "$(verdict_field "$v" Brief)" =~ ^(integrate|worker-no-patch|patch-guard|test-on-base)$ ]] \
     && { [ "$n" -eq 0 ] || ! cmp -s "$v" "${v%.md}.r$n.md"; }; then
    mkdir -p "$dir/state"; mv "$v" "$dir/state/$ticket.stale-verdict.md"
    if [ "$n" -gt 0 ]; then cp "${v%.md}.r$n.md" "$v"; fi
    printf '  %-40s stale: reviews %s, the ticket is integrated at %s; sent back to review (kept in state/%s.stale-verdict.md)\n' \
      "$(basename "$v")" "${vc:0:8}" "${marker:0:8}" "$ticket"
    continue
  fi
  # D117 (E33, E34): a new FAIL that failed no assertion and left more
  # unverified than passed (the guard, the environment or the review process
  # stopped its checks: 0/0/3 in E33, 1 pass and 13 unverified in eslint-10)
  # is no finding on the code. Rebuilding would redo working code against
  # nothing. Set aside, not a round, reviewed again; a second one in a row
  # escalates with the reviewer's reasons, a factory incident for a person.
  # D141: so does a FAIL whose reviewer wrote **Cause:** process (the review
  # couldn't finish, evidence no worker can produce): not a build round.
  if [ -n "$marker" ] && [ "$(verdict_field "$v" Result)" = FAIL ] \
     && { [ "$n" -eq 0 ] || ! cmp -s "$v" "${v%.md}.r$n.md"; }; then
    read -r vp vf vu < <(verdict_evidence_counts "$v")
    proc=""; [ "$(verdict_field "$v" Cause)" != process ] || proc=1
    if { [ "$vf" -eq 0 ] && [ "$vu" -gt "$vp" ]; } || [ -n "$proc" ]; then
      nr="$dir/state/$ticket.not-run"; k=$(( $(cat "$nr" 2>/dev/null || echo 0) + 1 )); echo "$k" > "$nr"
      mv "$v" "$dir/state/$ticket.not-run-verdict.md"
      if [ "$n" -gt 0 ]; then cp "${v%.md}.r$n.md" "$v"; fi
      if [ "$k" -ge 2 ]; then
        { printf 'two reviews in a row judged too little (no assertion failed, most unverified); the reviewer said:\n'
          sed -n '/^## Assertions/,/^## [^A]/p' "$dir/state/$ticket.not-run-verdict.md" | grep -E '^- ' | head -8
          grep -E '^- \[(blocking|process)\]' "$dir/state/$ticket.not-run-verdict.md" | head -4; } > "$dir/state/$ticket.stuck"
        printf '  %-40s judged too little again: escalated, see state/%s.stuck\n' "$(basename "$v")" "$ticket"
      else
        why="judged too little ($vp pass, 0 fail, $vu unverified)"; [ -z "$proc" ] || why="failed on the process, not the code (**Cause:** process)"
        printf '  %-40s %s: not a round; next.sh sends it back to review (kept in state/%s.not-run-verdict.md)\n' \
          "$(basename "$v")" "$why" "$ticket"
      fi
      continue
    fi
  fi
  record_verdict "$v" factory-reviewer; summary "$v"
  [[ "$(verdict_field "$v" Result)" =~ ^(PASS|FAIL)$ ]] && rm -f "$sent" "$dir/state/$ticket.invalid-verdict.md" "$dir/state/$ticket.no-verdict"
  # A review that judged something ends a run of reviews that judged nothing.
  read -r vp vf _ < <(verdict_evidence_counts "$v"); [ $((vp + vf)) -eq 0 ] || rm -f "$dir/state/$ticket.not-run"
done
# D69 for the mission verdicts too: a behavior or health verdict without a
# PASS/FAIL Result line is a format slip, not a failure. Recorded as-is it read
# as FAIL and sent the mission to fix tickets for findings nobody wrote (two
# missions stalled on it). Sent back once: next.sh asks for the run again.
mission_verdict() {                    # <stem> <role>
  local v="$dir/verdicts/$1.md" sent="$dir/state/$1.sent-back" n
  [ -f "$v" ] || return 0
  n="$(verdict_history_count "$v")"
  if ! [[ "$(verdict_field "$v" Result)" =~ ^(PASS|FAIL)$ ]] \
     && { [ "$n" -eq 0 ] || ! cmp -s "$v" "${v%.md}.r$n.md"; } && [ ! -f "$sent" ]; then
    mkdir -p "$dir/state"; mv "$v" "$dir/state/$1.invalid-verdict.md"; echo "$n" > "$sent"
    # No verdict file: next.sh asks for validate (or steward) again, not for fixes.
    printf '  %-40s sent back: no **Result:** PASS or FAIL line; run the step again (kept in state/%s.invalid-verdict.md)\n' "$1.md" "$1"
    return 0
  fi
  record_verdict "$v" "$2"; summary "$v"
  [[ "$(verdict_field "$v" Result)" =~ ^(PASS|FAIL)$ ]] && rm -f "$sent" "$dir/state/$1.invalid-verdict.md"
  return 0
}
mission_verdict behavior factory-validator
mission_verdict health factory-code-steward
bash "$here/usage.sh" "$feature" >/dev/null 2>&1 || true   # D85
bash "$here/archive.sh" collect "$feature" >/dev/null 2>&1 || true   # D97
bash "$here/checkpoint.sh" "$feature" >/dev/null
