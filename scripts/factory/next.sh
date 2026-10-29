#!/usr/bin/env bash
# Reads a mission's files and prints its state and the next step.
# The first output line is machine-readable for the lead (/factory):
#   STEP: <code>
# Codes (human steps marked *, they notify you):
#   paused* grill* context-sync investigate approve-conclusion* handoff* report*
#   contract approve* design approve-design* decide* tickets approve-tickets* coverage*
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
# D101: an approval line with no human.sh row in decisions.tsv approves nothing.
UNRECORDED="The approval line has no /factory-approve record in decisions.tsv (written by hand or by an agent): it does not count. Approve with /factory-approve."
STATUS=""
shopt -s nullglob

HUMAN_STEPS=" paused grill approve-conclusion handoff report approve approve-design decide approve-tickets coverage setup escalate blocked unverified pr "

step() {                                  # <code> <human explanation>
  local code="$1"; shift
  [[ "$HUMAN_STEPS" == *" $code "* ]] && notify "Factory: $feature waits for you" "$code: $*"
  printf 'STEP: %s\n' "$code"
  printf 'Mission: %s (%s)\n' "$feature" "$dir"
  [ -n "$STATUS" ] && printf '%s' "$STATUS"
  printf '\nNEXT → %s\n' "$*"
  exit 0
}

# D67: a misspelled name or a switched branch stops here, before any step.
if ! why="$(mission_guard "$feature")"; then step blocked "$why"; fi
# D88: a misspelled "## Frozen paths" heading would silently unfreeze the code
# the mission must not touch; stop before any step builds on it.
if [ -f "$spec" ] && bad="$(grep -nE '^#{1,6}[[:space:]]*[Ff]rozen' "$spec" | grep -vE ':## Frozen (paths|tests)[[:space:]]*$' | head -1)" && [ -n "$bad" ]; then
  step blocked "spec.md line ${bad%%:*} reads \"${bad#*:}\": the heading must be exactly \"## Frozen paths\" or \"## Frozen tests\", or the patch guard freezes nothing. Fix it, then next.sh again"
fi
# D93: a refactor is only safe against tests that pin today's behavior.
if [ -f "$spec" ] && [ "$(verdict_field "$spec" Intent)" = refactor ]; then
  ft="$(frozen_tests "$spec")"
  [ -n "$ft" ] || step blocked "a refactor needs the tests that pin today's behavior: list them under \"## Frozen tests\" in spec.md (e.g. - test/characterization/), then next.sh again"
  missing=""; while IFS= read -r p; do case "$p" in *[*?]*) continue ;; esac; [ -e "$p" ] || missing="$missing $p"; done <<<"$ft"
  [ -z "$missing" ] || step blocked "## Frozen tests names what doesn't exist here:$missing. Run the refactor on a branch that has the characterization tests"
fi
if [ -f "$dir/state/PAUSED.md" ]; then
  step paused "resume: scripts/factory/pause.sh resume $feature (shows where it stopped), then next.sh again"
fi
if [ -f "$dir/state/open-question.md" ]; then
  STATUS="$(cat "$dir/state/open-question.md")"$'\n'
  step decide "human: answer with /factory-decide $feature <your answer, and why>. Irreversible choices never default (D47)."
fi
[ -f "$spec" ] || step grill "human, main session: /grill-with-docs, then /to-spec → $spec"

# D99: a bug between services is investigated before any contract. Context
# repos are cloned read-only; explorers map one repo each, fresh; the
# investigator concludes where the fix belongs and how to reproduce it.
if investigation_applies "$spec"; then
  inv="$dir/investigation.md"; intent="$(verdict_field "$spec" Intent)"
  if ! out="$(bash "$here/context.sh" check "$feature" 2>&1)"; then
    STATUS="$out"$'\n'
    step context-sync "scripts/factory/context.sh sync $feature (clone the context repos read-only, record the commits read)"
  fi
  rounds="$(investigation_rounds "$dir")"; limit="$FACTORY_INVESTIGATE_ROUNDS"
  need=""
  maps=""; while IFS= read -r n; do [ -s "$dir/context/$n.md" ] || maps+=" $n"; done < <(context_repos "$spec" | cut -f1; echo home)
  [ -z "$maps" ] || need="briefs for$maps"
  [ -n "$need" ] || [ -f "$inv" ] || need="the investigator's first pass"
  open="$(open_questions "$dir")"
  [ -n "$need" ] || [ -z "$open" ] || [ "$rounds" -ge "$limit" ] || need="answers to $(cut -f1 <<<"$open" | tr '\n' ' ' | sed 's/ $//')"
  if [ -z "$need" ] && ! grep -q '^## Conclusion' "$inv"; then need="a conclusion"; fi
  belongs="$(fix_belongs "$inv")"
  if [ -z "$need" ] && [ -z "$belongs" ]; then need="**Fix belongs:** in the conclusion (here, or a context repo)"; fi
  if [ -z "$need" ] && [ "$belongs" != here ] && ! context_repos "$spec" | cut -f1 | grep -qxF "$belongs"; then
    need="a **Fix belongs:** that names here or a context repo (it says $belongs)"
  fi
  if [ -z "$need" ] && [ "$belongs" != here ] && [ ! -s "$dir/finding-for-$belongs.md" ]; then
    need="the finding for $belongs (finding-for-$belongs.md)"
  fi
  if [ -z "$need" ] && [ "$belongs" = here ] && [ "$intent" = bugfix ]; then
    repro=""; for t in "$dir"/issues/*-reproduce-*.md; do [ -f "$t" ] && [ -n "$(verdict_field "$t" Test)" ] && repro="$t"; done
    [ -n "$repro" ] || need="a reproduction ticket (issues/01-reproduce-<slug>.md with a **Test:** line)"
  fi
  if [ -n "$need" ]; then
    STATUS="Investigation round $rounds of $limit"$'\n'
    if [ "$rounds" -lt "$limit" ]; then
      step investigate "scripts/factory/workflow.sh investigate $feature (missing: $need; explorers fresh, one repo each, then the investigator)"
    fi
    step escalate "human: the investigation used its $limit rounds and still lacks $need. Read $inv; add context to the spec, or raise FACTORY_INVESTIGATE_ROUNDS and run next.sh again"
  fi
  if ! conclusion_approved "$inv"; then
    hint=""; approval_unrecorded "$inv" Conclusion approve-conclusion && hint=" $UNRECORDED"
    step approve-conclusion "human: read $inv (and the reproduction ticket, if any), then /factory-approve $feature conclusion, or edit the spec and next.sh again.$hint"
  fi
  if [ "$belongs" != here ]; then
    step handoff "human: the fix belongs in $belongs. Send $dir/finding-for-$belongs.md to that repo's team. This mission changes nothing here; it ends at this step"
  fi
  if [ "$intent" = exploration ]; then
    step report "human: the approved investigation is the deliverable: $inv. Nothing is built; the mission ends here"
  fi
fi
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
  approval_unrecorded "$spec" Contract approve && hint="$hint $UNRECORDED"
  who="$(verdict_field "$spec" Reviewer)"
  step approve "G1, human${who:+ (and $who, who will review the MR)}: read the contract and $critique, then /factory-approve $feature (or /factory-amend $feature \"<change>\").$hint"
fi

# D94: the shape of the code, approved before any ticket (feature, refactor).
if design_needed "$spec"; then
  design="$dir/design.md"
  [ -f "$design" ] || step design "scripts/factory/workflow.sh design $feature (designer, fresh: call stacks, files, types and slices, per docs/agents/design-format.md)"
  if ! design_approved "$design"; then
    who="$(verdict_field "$spec" Reviewer)"; hint=""
    approval_unrecorded "$design" Design approve-design && hint=" $UNRECORDED"
    step approve-design "G1b, human${who:+ (and $who, who will review the MR)}: read $design, then /factory-approve $feature design. To change it, edit it or delete it and run next.sh (the designer writes it again).$hint"
  fi
fi

tickets=("$dir"/issues/*.md)
# D52: tickets come from the ticket writer (or by hand), and wait for a human.
if [ -f "$dir/state/tickets.pending" ]; then
  STATUS="$(cat "$dir/state/tickets.pending")"$'\n'"Tickets now: $(ls "$dir/issues" 2>/dev/null | tr '\n' ' ')"$'\n'
  step approve-tickets "human: review .scratch/$feature/issues/ (edit, split or delete freely), then /factory-approve $feature tickets"
fi
# D99: an investigation's reproduction ticket alone doesn't replace the ticket writer.
only_repro=1; for t in "${tickets[@]}"; do [[ "$(basename "$t")" == *-reproduce-* ]] || only_repro=0; done
if [ ${#tickets[@]} -eq 0 ] || { [ "$only_repro" = 1 ] && ! grep -q $'\tapprove-tickets\t' "$dir/decisions.tsv" 2>/dev/null; }; then
  step tickets "scripts/factory/workflow.sh tickets $feature all (ticket writer, fresh; you approve the result). Or write them by hand per docs/agents/ticket-format.md."
fi

if ! out="$(bash "$here/coverage.sh" "$feature" 2>&1)"; then
  STATUS="$out"$'\n'
  step coverage "fix '## Covers' in the tickets, or amend the contract (G2)"
fi

load_commands
if [ -z "$FACTORY_TEST_CMD" ] && [ "${FACTORY_ALLOW_NO_TESTS:-0}" != "1" ]; then
  step setup "human: factory setup --write (finds and rehearses the test and lint commands, D102), or set FACTORY_TEST_CMD in .factory/commands.env yourself; then commit it. The factory never integrates without tests (D44)."
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
  later=""; [ ${#T_ESCALATE[@]} -gt 0 ] && later="; ${T_ESCALATE[*]} wait for the human afterwards, run this step now"
  step review "scripts/factory/workflow.sh review-wave $feature (${#T_REVIEW[@]} ticket(s); fresh reviewers, other family$later)"
fi
if [ ${#T_BUILD[@]} -gt 0 ]; then
  extra=""
  [ ${#T_BUILD[@]} -gt "$FACTORY_MAX_PARALLEL" ] && extra=", first $FACTORY_MAX_PARALLEL of ${#T_BUILD[@]}"
  # The table may show ESCALATE or blocked tickets: they wait for the human
  # after this step, they don't stop it.
  [ ${#T_ESCALATE[@]} -gt 0 ] && extra+="; ${T_ESCALATE[*]} wait for the human afterwards, run this step now"
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

step pr "scripts/factory/metrics.sh $feature → /pr (Evidence, written to $dir/pr.md) → scripts/factory/mr.sh $feature opens the MR → /skill:mission-retro (private: retro.sh save)"
