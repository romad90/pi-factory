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
tickets=0; fixes=0; first_pass=0; rounds=0; reviewed=0; tokens=0; det_fail=0; unchecked=0
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
    case "$(verdict_field "$h" Brief)" in integrate|worker-no-patch|patch-guard) det_fail=$((det_fail + 1)) ;; esac
    grep -qE "worker's last self-check: (never run|FAIL)" "$h" 2>/dev/null && unchecked=$((unchecked + 1))
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
health="-"; steward="-"
[ -f "$dir/health/report.md" ] && health="$(verdict_field "$dir/health/report.md" Result)"
if [ -f "$dir/verdicts/health.md" ]; then
  read -r hp hf hu < <(verdict_evidence_counts "$dir/verdicts/health.md")
  steward="$(verdict_field "$dir/verdicts/health.md" Result) (round $(verdict_round "$dir/verdicts/health.md")): $hp met, $hf failed, $hu unverified"
fi
guard=0
for h in "$dir"/verdicts/*-code.r*.md; do [ "$(verdict_field "$h" Brief)" = patch-guard ] && guard=$((guard + 1)); done
decisions=0; auto=0
if [ -f "$dir/decisions.tsv" ]; then      # P8: human interventions vs questions the resolver settled (D70)
  auto="$(awk -F'\t' 'NR > 1 && $3 == "auto"' "$dir/decisions.tsv" | wc -l | tr -d ' ')"
  decisions=$(( $(wc -l < "$dir/decisions.tsv") - 1 - auto ))
fi
usage_line="-"
if [ -s "$dir/usage.tsv" ]; then      # D85: tokens per run, from pi-subagents' metadata
  usage_line="$(awk -F'\t' 'NR > 1 { r++; i += $5; o += $6; c += $7; t += $10; if ($4 ~ /worker/) w += $5 + $6 }
    END { printf "%d runs · %.1fM in (%.0f%% cached), %.1fk out · %d turns · workers %.1fM", r, i / 1e6, (i ? 100 * c / i : 0), o / 1e3, t, w / 1e6 }' "$dir/usage.tsv")"
fi
models_list=""
[ ${#models[@]} -gt 0 ] && models_list="$(printf '%s\n' "${models[@]}" | sort -u | paste -sd, - | sed 's/,/, /g')"
# D77: every role's models, from the runs workflow.sh recorded (judges only before).
if [ -s "$dir/runs.tsv" ]; then
  models_list="$(awk -F'\t' 'NR > 1 && $5 != "" { k = $4 ": " $5 ($6 != "" ? " (" $6 ")" : ""); if (!(k in seen)) { seen[k] = 1; n[$4]++ } c[k]++ }
    END { for (k in c) print k " ×" c[k] }' "$dir/runs.tsv" | sort | paste -sd';' - | sed 's/;/; /g')"
fi

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
| Failed integrations handed over without a passing self-check (D78) | $unchecked |
| Behavior validation rounds | ${behavior_rounds:--} |
| Behavior assertions (evidence or label) | $evidence |
| Code health: ratchet and repo tool (G5) | $health |
| Code steward, quality bar items (G5) | $steward |
| Patches blocked by the patch guard | $guard |
| Human decisions logged (target: 5 or fewer, P8) | $decisions |
| Questions answered by the resolver (auto, unreviewed until a human reads them) | $auto |
| Cycle time (first → last mission commit) | $cycle |
| Tokens reported in verdicts | $( [ "$tokens" -gt 0 ] && echo "$tokens" || echo "not reported" ) |
| Models used (role: model ×runs) | ${models_list:--} |
| Tokens (usage.tsv, D85) | $usage_line |
EOF
