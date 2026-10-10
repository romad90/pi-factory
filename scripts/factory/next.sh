#!/usr/bin/env bash
# Reads a mission's files and prints its state and the next step.
# The first output line is machine-readable for the lead (/factory):
#   STEP: <code>
# Codes (human steps marked *, they notify you):
#   paused* grill* contract approve* decide* tickets approve-tickets* coverage*
#   setup* build review escalate* blocked* validate behavior-fix
#   behavior-stale health health-fix steward unverified* pr*
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
shopt -s nullglob

HUMAN_STEPS=" paused grill approve decide approve-tickets coverage setup escalate blocked unverified pr "

step() {                                  # <code> <human explanation>
  local code="$1"; shift
  [[ "$HUMAN_STEPS" == *" $code "* ]] && notify "Factory: $feature waits for you" "$code: $*"
  printf 'STEP: %s\n' "$code"
  printf 'Mission: %s (%s)\n' "$feature" "$dir"
  [ -n "$STATUS" ] && printf '%s' "$STATUS"
  printf '\nNEXT → %s\n' "$*"
  exit 0
}

if [ -f "$dir/state/PAUSED.md" ]; then
  step paused "resume: scripts/factory/pause.sh resume $feature (shows where it stopped), then next.sh again"
fi
if [ -f "$dir/state/open-question.md" ]; then
  STATUS="$(cat "$dir/state/open-question.md")"$'\n'
  step decide "human: answer with /factory-decide $feature <answer> <why>. Irreversible choices never default (D47)."
fi
[ -f "$spec" ] || step grill "human, main session: /grill-with-docs, then /to-spec → $spec"
pending_amendment=""
for a in "$dir"/amendments/*.md; do
  [ -f "$a" ] && grep -q '^\*\*Status:\*\* pending' "$a" && pending_amendment="$a"
done
if ! has_contract "$spec" || [ ! -f "$critique" ] || [ -n "$pending_amendment" ]; then
  step contract "scripts/factory/workflow.sh contract $feature (author, then critic, fresh, other families)"
fi
if ! contract_approved "$spec"; then
  hint=""
  grep -q '\[blocking\]' "$critique" && hint=" The critique has [blocking] findings: rerun 'workflow.sh contract' to amend, then re-read."
  step approve "G1, human: read the contract and $critique, then /factory-approve $feature (or /factory-amend $feature \"<change>\").$hint"
fi

tickets=("$dir"/issues/*.md)
# D52: tickets come from the ticket writer (or by hand), and wait for a human.
if [ -f "$dir/state/tickets.pending" ]; then
  STATUS="$(cat "$dir/state/tickets.pending")"$'\n'"Tickets now: $(ls "$dir/issues" 2>/dev/null | tr '\n' ' ')"$'\n'
  step approve-tickets "human: review .scratch/$feature/issues/ (edit, split or delete freely), then /factory-approve $feature tickets"
fi
[ ${#tickets[@]} -gt 0 ] || step tickets "scripts/factory/workflow.sh tickets $feature all (ticket writer, fresh; you approve the result). Or write them by hand per docs/agents/ticket-format.md."

if ! out="$(bash "$here/coverage.sh" "$feature" 2>&1)"; then
  STATUS="$out"$'\n'
  step coverage "fix '## Covers' in the tickets, or amend the contract (G2)"
fi

load_commands
if [ -z "$FACTORY_TEST_CMD" ] && [ "${FACTORY_ALLOW_NO_TESTS:-0}" != "1" ]; then
  step setup "human: set FACTORY_TEST_CMD (and FACTORY_LINT_CMD) in .factory/commands.env and commit it. The factory never integrates without tests (D44)."
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
  step build "scripts/factory/workflow.sh build-wave $feature (${#T_BUILD[@]} ticket(s)$extra), then integrate.sh per patch"
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
  # Code changed since the failing verdict (fix tickets built): validate again.
  verdict_is_fresh "$(verdict_field "$b" Commit)" \
    || step validate "fix tickets are built since the failing behavior verdict: scripts/factory/workflow.sh validate $feature"
  if [ -n "$n" ] && [ "$n" -ge "$FACTORY_ROUND_LIMIT" ]; then
    step escalate "human: behavior still failing at round $n. Review the contract (/factory-amend)."
  fi
  step behavior-fix "scripts/factory/workflow.sh tickets $feature fix-behavior (one fix ticket per finding in $b; you approve them, D25, D52)"
fi
behavior_verdict_is_fresh "$(verdict_field "$b" Commit)" \
  || step behavior-stale "behavior paths changed since the behavior verdict: scripts/factory/workflow.sh validate $feature"

# D40: unverified assertions are not passes. Ship them only on a human's word.
unverified_step() {                    # <verdict> <label>
  local accepted id missing=""
  accepted=" $(accepted_unverified "$spec" | tr '\n' ' ') "
  for id in $(verdict_unverified_ids "$1"); do
    [[ "$accepted" == *" ALL "* || "$accepted" == *" $id "* ]] || missing+=" $id"
  done
  if [ -n "$missing" ]; then
    step unverified "human: $2 PASS leaves${missing} unverified. Prove them, or /factory-accept-unverified $feature <ids|ALL> <why> to ship them as Known limits."
  fi
}
unverified_step "$b" behavior

# G5, code health (D49, D50): the deterministic ratchet first, then the steward.
report="$dir/health/report.md"; h="$dir/verdicts/health.md"
if [ ! -f "$report" ] || ! code_verdict_is_fresh "$(verdict_field "$report" Commit)"; then
  step health "scripts/factory/health.sh check $feature (ratchet + repo tool; no model involved)"
fi
if [ "$(verdict_field "$report" Result)" != "PASS" ]; then
  STATUS="$(sed -n '/^## Ratchet/,/^## Changed/p' "$report")"$'\n'
  step health-fix "scripts/factory/workflow.sh tickets $feature fix-health (the health report fails; one fix ticket per cause). If a worse metric is justified, a human runs health.sh baseline and commits it with the reason."
fi
if [ ! -f "$h" ] || ! code_verdict_is_fresh "$(verdict_field "$h" Commit)"; then
  step steward "scripts/factory/workflow.sh steward $feature (code steward, fresh, other family; judges the whole mission diff against docs/agents/quality-bar.md)"
fi
if [ "$(verdict_field "$h" Result)" != "PASS" ]; then
  n="$(verdict_round "$h")"
  if [ -n "$n" ] && [ "$n" -ge "$FACTORY_ROUND_LIMIT" ]; then
    step escalate "human: code health still failing at round $n. Discuss the quality bar or the design."
  fi
  step health-fix "scripts/factory/workflow.sh tickets $feature fix-health (one fix ticket per finding in $h; you approve them)"
fi
unverified_step "$h" "code steward"

step pr "scripts/factory/metrics.sh $feature → /pr (Evidence), open the MR, then /retro"
