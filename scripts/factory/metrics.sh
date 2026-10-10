#!/usr/bin/env bash
# Per-mission metrics, from the mission's files and git history (D26).
# Paste the output into the MR's Evidence section via /pr. Across missions,
# these are the numbers that show whether Step 2 is real (ADR-001 §10).
#
# Usage: scripts/factory/metrics.sh <feature>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: metrics.sh <feature>}"
dir="$(mission_dir "$feature")"
spec="$dir/spec.md"
[ -f "$spec" ] || die "no spec at $spec"

intent="$(verdict_field "$spec" Intent)"
assertions="$(contract_ids "$spec" | grep -c . || true)"
amendments="$(grep -cE '^\s*- \*\*(Amended|Withdrawn):\*\*' "$spec" || true)"

shopt -s nullglob
tickets=0; fixes=0; first_pass=0; rounds=0; reviewed=0; tokens=0; det_fail=0
for t in "$dir"/issues/*.md; do
  tickets=$((tickets + 1))
  name="$(ticket_name "$t")"
  [[ "$name" == *-fix-* ]] && fixes=$((fixes + 1))
  v="$dir/verdicts/${name}-code.md"
  [ -f "$v" ] || continue
  reviewed=$((reviewed + 1))
  n="$(verdict_round "$v")"; n="${n:-1}"
  rounds=$((rounds + n))
  # D38: first pass = the first recorded round passed (history, not the agent's word).
  r1="${v%.md}.r1.md"; [ -f "$r1" ] || r1="$v"
  [ "$(verdict_field "$r1" Result)" = "PASS" ] && first_pass=$((first_pass + 1))
  for h in "${v%.md}".r*.md; do
    case "$(verdict_field "$h" Brief)" in integrate|worker-no-patch) det_fail=$((det_fail + 1)) ;; esac
  done
done

models=(); behavior_rounds="-"; evidence="-"
for v in "$dir"/verdicts/*.md; do
  [[ "$v" =~ \.r[0-9]+\.md$ ]] && continue
  m="$(verdict_field "$v" Model)"; [ -n "$m" ] && [ "$m" != none ] && models+=("$m")
  k="$(verdict_field "$v" Tokens)"; [[ "$k" =~ ^[0-9]+$ ]] && tokens=$((tokens + k))
done
b="$dir/verdicts/behavior.md"
if [ -f "$b" ]; then
  behavior_rounds="$(verdict_round "$b")"
  read -r ep ef eu < <(verdict_evidence_counts "$b")
  evidence="$ep proven, $ef failed, $eu unverified"
fi
decisions=0
[ -f "$dir/decisions.tsv" ] && decisions=$(( $(wc -l < "$dir/decisions.tsv") - 1 ))
models_list=""
[ ${#models[@]} -gt 0 ] && models_list="$(printf '%s\n' "${models[@]}" | sort -u | paste -sd, - | sed 's/,/, /g')"

first="$(git log --reverse --format=%ct -- "$dir" | awk 'NR == 1')"
last="$(git log -1 --format=%ct -- "$dir")"
cycle="-"
if [ -n "$first" ] && [ -n "$last" ]; then
  h=$(( (last - first) / 3600 ))
  cycle="$((h / 24))d $((h % 24))h"
fi

pct() { [ "$2" -gt 0 ] && echo "$(( 100 * $1 / $2 ))%" || echo "-"; }

cat <<EOF
### Factory metrics: $feature

| Metric | Value |
|---|---|
| Intent | ${intent:-not set} |
| Assertions in contract | $assertions |
| Contract amendments after drafting | $amendments |
| Tickets (of which fix tickets) | $tickets ($fixes) |
| First-pass review rate | $(pct "$first_pass" "$reviewed") ($first_pass/$reviewed) |
| Rounds, total (of which deterministic fails: integration, no patch) | $rounds ($det_fail) |
| Behavior validation rounds | ${behavior_rounds:--} |
| Behavior assertions (evidence or label) | $evidence |
| Human decisions logged | $decisions |
| Cycle time (first → last mission commit) | $cycle |
| Tokens reported in verdicts | $( [ "$tokens" -gt 0 ] && echo "$tokens" || echo "not reported" ) |
| Models used (configured, from collect.sh) | ${models_list:--} |
EOF
