#!/usr/bin/env bash
# Reads a mission's files and prints its state and the next step.
# The first output line is machine-readable for the lead (/factory):
#   STEP: <code>
# Codes: grill contract approve tickets coverage build review escalate
#        blocked validate behavior-fix behavior-stale pr
#
# Usage: scripts/factory/next.sh <feature>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: next.sh <feature>}"
dir="$(mission_dir "$feature")"
spec="$dir/spec.md"
critique="$dir/contract-critique.md"
STATUS=""

step() {                                  # <code> <human explanation>
  local code="$1"; shift
  printf 'STEP: %s\n' "$code"
  printf 'Mission: %s (%s)\n' "$feature" "$dir"
  [ -n "$STATUS" ] && printf '%s' "$STATUS"
  printf '\nNEXT → %s\n' "$*"
  exit 0
}

[ -f "$spec" ] || step grill "human, main session: /grill-with-docs, then /to-spec → $spec"
if ! has_contract "$spec" || [ ! -f "$critique" ]; then
  step contract "scripts/factory/workflow.sh contract $feature (author, then critic, fresh, other families)"
fi
if ! contract_approved "$spec"; then
  hint=""
  grep -q '\[blocking\]' "$critique" && hint=" The critique has [blocking] findings: rerun 'workflow.sh contract' to amend, then re-read."
  step approve "G1, human: read the contract and $critique, then add '**Contract approved:** $(date +%F)' under the contract heading.$hint"
fi

shopt -s nullglob
tickets=("$dir"/issues/*.md)
[ ${#tickets[@]} -gt 0 ] || step tickets "human, main session: /to-tickets (each ticket needs '## Covers'), then checkpoint.sh"

if ! out="$(bash "$here/coverage.sh" "$feature" 2>&1)"; then
  STATUS="$out"$'\n'
  step coverage "fix '## Covers' in the tickets, or amend the contract (G2)"
fi

compute_ticket_state "$feature"
in_list() { local x="$1"; shift; local y; for y in "$@"; do [ "$x" = "$y" ] && return 0; done; return 1; }
STATUS="Tickets"$'\n'
for t in "${tickets[@]}"; do
  name="$(ticket_name "$t")"; num="$(ticket_num "$t")"; state="build"
  [ -n "${T_PASSED[$num]:-}" ] && state="PASS"
  in_list "$name" "${T_REVIEW[@]}"   && state="review"
  in_list "$name" "${T_ESCALATE[@]}" && state="ESCALATE"
  in_list "$name" "${T_BLOCKED[@]}"  && state="blocked"
  STATUS+="$(printf '  %-36s %-9s round %s' "$name" "$state" "${T_ROUND[$name]:-0}")"$'\n'
done

if [ ${#T_REVIEW[@]} -gt 0 ]; then
  step review "scripts/factory/workflow.sh review-wave $feature (${#T_REVIEW[@]} ticket(s); fresh reviewers, other family)"
fi
if [ ${#T_BUILD[@]} -gt 0 ]; then
  extra=""
  [ ${#T_BUILD[@]} -gt "$FACTORY_MAX_PARALLEL" ] && extra=", first $FACTORY_MAX_PARALLEL of ${#T_BUILD[@]}"
  step build "scripts/factory/checkpoint.sh $feature, then workflow.sh build-wave $feature (${#T_BUILD[@]} ticket(s)$extra), then integrate.sh per patch"
fi
if [ ${#T_ESCALATE[@]} -gt 0 ]; then
  step escalate "human: ${T_ESCALATE[*]} failed $FACTORY_ROUND_LIMIT rounds. Usually the contract or spec is wrong: consider 'workflow.sh contract' (amend)."
fi
if [ ${#T_BLOCKED[@]} -gt 0 ]; then
  step blocked "human: ${T_BLOCKED[*]} can't start. Check '## Blocked by' for cycles."
fi

b="$dir/verdicts/behavior.md"
[ -f "$b" ] || step validate "scripts/factory/workflow.sh validate $feature (fresh, main checkout, holds the instrument)"
r="$(verdict_field "$b" Result)"; n="$(verdict_round "$b")"
if [ "$r" != "PASS" ]; then
  if [ -n "$n" ] && [ "$n" -ge "$FACTORY_ROUND_LIMIT" ]; then
    step escalate "human: behavior still failing at round $n. Review the contract ('workflow.sh contract' to amend)."
  fi
  step behavior-fix "human (orchestrator, D25): turn each finding in $b into one fix ticket (issues/NN-fix-<slug>.md, '## Covers' = its assertions), then checkpoint.sh"
fi
verdict_is_fresh "$(verdict_field "$b" Commit)" \
  || step behavior-stale "code changed since the behavior verdict: scripts/factory/workflow.sh validate $feature"

step pr "scripts/factory/metrics.sh $feature → /pr (Evidence), open the MR, then /retro"
