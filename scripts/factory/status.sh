#!/usr/bin/env bash
# A read-only snapshot of the factory for the cockpit (P10, D90): derived from
# the files the mission already has (next.sh's step, tickets, verdicts and
# their round copies, journals, decisions.tsv, runs.tsv, usage.tsv, the
# mission's commits). Nothing new to keep in sync: delete the snapshot and it
# comes back the same.
#
# Usage: scripts/factory/status.sh <mission> --json   one mission
#        scripts/factory/status.sh --all --json       every mission (the leads)
# Live workers are read, best effort, from pi-subagents' async run logs under
# $FACTORY_RUN_DIRS (space-separated; default: the temp folder's
# pi-subagents-uid-<uid>/async-subagent-runs).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

all=""; json=""; feature=""
for a in "$@"; do
  case "$a" in --all) all=1 ;; --json) json=1 ;; -*) die "unknown option: $a" ;; *) feature="$a" ;; esac
done
[ -n "$json" ] || die "usage: status.sh <mission>|--all --json (for the text view, run next.sh)"
[ -n "$all" ] || [ -n "$feature" ] || die "usage: status.sh <mission>|--all --json"

HUMAN_STEPS=" paused grill approve decide approve-tickets coverage setup escalate blocked unverified pr "

# One mission → tab-separated lines node turns into JSON:
#   S <step> / N <next> / H <1 if a human step> / O <branch holding the state>
#   T <name> <num> <state> <round> <blocked by,> <covers,> <integrated marker>
mission_lines() {
  local f="$1" dir out t name num state
  dir="$(mission_dir "$f")"
  # A mission whose latest state is on another branch is not waiting for
  # anyone here (D67): say where it lives, without running its steps.
  if ! why="$(mission_guard "$f")" && [[ "$why" == *"is on branch '"* ]]; then
    printf 'S\tother-branch\nN\t%s\nH\t0\nO\t%s\n' "$why" "$(printf '%s' "$why" | sed -n "s/.*is on branch '\([^']*\)'.*/\1/p")"
    return 0
  fi
  out="$(FACTORY_NOTIFY=0 bash "$here/next.sh" "$f" 2>/dev/null || true)"
  printf 'S\t%s\n' "$(printf '%s\n' "$out" | sed -n 's/^STEP: //p' | head -1)"
  printf 'N\t%s\n' "$(printf '%s\n' "$out" | sed -n 's/^NEXT → //p' | head -1)"
  printf 'H\t%s\n' "$([[ "$HUMAN_STEPS" == *" $(printf '%s\n' "$out" | sed -n 's/^STEP: //p' | head -1) "* ]] && echo 1 || echo 0)"
  shopt -s nullglob
  local tickets=("$dir"/issues/*.md)
  [ ${#tickets[@]} -gt 0 ] || return 0
  compute_ticket_state "$f"
  local -A st=()
  for name in "${T_REVIEW[@]}"; do st[$name]=review; done
  for name in "${T_ESCALATE[@]}"; do st[$name]=escalate; done
  for name in "${T_BLOCKED[@]}"; do st[$name]=blocked; done
  for name in "${T_BUILD[@]}"; do st[$name]=build; done
  for t in "${tickets[@]}"; do
    name="$(ticket_name "$t")"; num="$(ticket_num "$t")"
    state="${st[$name]:-build}"; [ -n "${T_PASSED[$num]:-}" ] && state=pass
    printf 'T\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$num" "$state" "${T_ROUND[$name]:-0}" \
      "$(ticket_blockers "$t" | paste -sd, -)" "$(ticket_covers "$t" | paste -sd, -)" "$(ticket_marker "$f" "$name")"
  done
}

missions=()
if [ -n "$all" ]; then
  shopt -s nullglob
  for s in "$FACTORY_DIR"/*/spec.md "$FACTORY_DIR"/*/issues; do missions+=("$(basename "$(dirname "$s")")"); done
  [ ${#missions[@]} -eq 0 ] || mapfile -t missions < <(printf '%s\n' "${missions[@]}" | sort -u)
else
  [ -d "$(mission_dir "$feature")" ] || die "no mission '$feature' in $FACTORY_DIR/"
  missions=("$feature")
fi

runs="${FACTORY_RUN_DIRS:-${TMPDIR:-/tmp}/pi-subagents-uid-$(id -u)/async-subagent-runs}"
# D97: the leads level carries the factory's totals across missions (cost per
# MR, interventions per MR, first pass, scores), for the factory engineer.
# FACTORY_STATUS_METRICS=0 leaves them out.
metrics=""
if [ -n "$all" ] && [ "${FACTORY_STATUS_METRICS:-1}" != 0 ] && [ ${#missions[@]} -gt 0 ]; then
  metrics="$(mktemp)"; trap 'rm -f "$metrics"' EXIT
  bash "$here/metrics.sh" --all --json > "$metrics" 2>/dev/null || : > "$metrics"
fi
{
  for f in "${missions[@]}"; do printf 'M\t%s\n' "$f"; mission_lines "$f"; done
} | FACTORY_DIR="$FACTORY_DIR" RUN_DIRS="$runs" ALL="$all" METRICS="$metrics" QUIET_MIN="${FACTORY_QUIET_MIN:-10}" node "$here/status.mjs"
