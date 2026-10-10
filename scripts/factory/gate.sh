#!/usr/bin/env bash
# Factory gates G1–G4. Run by GitLab CI on every merge request, so the gates
# hold however tired or rushed anyone is. See ADR-001 §5 (D9–D11, D23).
#
# Usage:
#   scripts/factory/gate.sh mission <feature>   check one mission (local)
#   scripts/factory/gate.sh mr <base-ref>       check what an MR touches (CI)
#
# Exit: 0 = gates pass, 1 = a gate fails, 2 = usage / missing inputs
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

fail=0
ok()  { printf '  ✓ %s\n' "$*"; }
bad() { printf '  ✗ %s\n' "$*"; fail=1; }

check_verdict() {                       # <file> <label>
  local f="$1" label="$2" r n
  if [ ! -f "$f" ]; then bad "$label: verdict missing ($f)"; return; fi
  r="$(verdict_field "$f" Result)"
  n="$(verdict_round "$f")"
  if [ "$r" = "PASS" ]; then
    ok "$label: PASS (round ${n:-?})"
  elif [ -n "$n" ] && [ "$n" -ge "$FACTORY_ROUND_LIMIT" ]; then
    bad "$label: FAIL at round $n, limit reached. Escalate: amend the contract or the spec."
  else
    bad "$label: ${r:-no result} (round ${n:-?})"
  fi
}

warn() { printf '  ! %s\n' "$*"; }

# D38: a verdict counts only once collect.sh recorded it (round from history).
check_recorded() {                      # <file> <label>
  local f="$1" label="$2" latest n
  [ -f "$f" ] || return 0
  n="$(verdict_history_count "$f")"; latest="${f%.md}.r$n.md"
  if [ "$n" -eq 0 ]; then bad "$label: verdict not recorded (run scripts/factory/collect.sh); rounds come from history, never from the agent"
  elif ! cmp -s "$f" "$latest"; then bad "$label: verdict changed after it was recorded (run collect.sh)"; fi
}

# D39: the model in a verdict is the configured one, written by collect.sh.
check_model() {                         # <file> <label> <agent>
  local f="$1" label="$2" want got
  [ -f "$f" ] || return 0
  want="$(agent_model "$3")"; got="$(verdict_field "$f" Model)"
  [ "$got" = "none" ] && return 0
  [ "$got" = "$want" ] || warn "$label: verdict model '${got:-none}' ≠ configured $3 model '$want' (model changed since?)"
}

# D40: evidence or label. Unverified assertions only ship on a human's word.
check_evidence() {                      # <file> <label> <spec>
  local f="$1" label="$2" spec="$3" accepted id missing="" p u
  [ -f "$f" ] && [ "$(verdict_field "$f" Result)" = "PASS" ] || return 0
  read -r p _ u < <(verdict_evidence_counts "$f")
  accepted=" $(accepted_unverified "$spec" | tr '\n' ' ') "
  for id in $(verdict_unverified_ids "$f"); do
    [[ "$accepted" == *" ALL "* || "$accepted" == *" $id "* ]] || missing+=" $id"
  done
  if [ -n "$missing" ]; then bad "$label: unverified, not accepted:$missing (prove them or /factory-accept-unverified)"
  else ok "$label: $p proven, $u accepted unverified"; fi
}

check_fresh() {                         # <file> <label> [behavior]
  local f="$1" label="$2" sha fresh=verdict_is_fresh
  [ -f "$f" ] || return 0
  [ "${3:-}" = behavior ] && fresh=behavior_verdict_is_fresh
  sha="$(verdict_field "$f" Commit)"
  if "$fresh" "$sha"; then
    ok "$label: verdict matches current code (${sha:0:8})"
  else
    bad "$label: verdict is stale or has no valid **Commit:** line; code changed after it was produced"
  fi
}

# D32: a PASS verdict must carry the id of a factory-generated brief for that
# role, scope, ticket and commit. Proves the reviewer was dispatched with a
# file-paths-only brief rather than a hand-written one.
check_brief() {                         # <file> <label> <role> <scope> <ticket>
  local f="$1" label="$2" got commit want
  [ -f "$f" ] && [ "$(verdict_field "$f" Result)" = "PASS" ] || return 0
  got="$(verdict_field "$f" Brief)"; commit="$(verdict_field "$f" Commit)"
  want="$(brief_id "$3" "$4" "$5" "$commit")"
  if [ "$got" = "$want" ]; then ok "$label: dispatched with a generated brief"
  else bad "$label: brief id '${got:-none}' doesn't match the generated brief ($want); re-dispatch via workflow.sh"; fi
}

check_mission() {                       # <feature>
  local feature="$1" dir spec t name cov
  dir="$(mission_dir "$feature")"; spec="$dir/spec.md"
  echo "Mission: $feature"

  if [ ! -f "$spec" ]; then bad "spec.md missing"; return; fi
  if ! has_contract "$spec"; then bad "G1: no validation contract"; return; fi

  if [ -f "$dir/contract-critique.md" ]; then ok "G1: contract critique present"
  else bad "G1: contract critique missing (run /contract-critic)"; fi

  if contract_approved "$spec"; then ok "G1: contract approved"
  else bad "G1: contract not approved (or amended and awaiting re-approval)"; fi

  cov="$(mktemp)"
  if bash "$here/coverage.sh" "$feature" >"$cov" 2>&1; then ok "G2: coverage"
  else bad "G2: coverage"; sed 's/^/      /' "$cov"; fi
  rm -f "$cov"

  shopt -s nullglob
  for t in "$dir"/issues/*.md; do
    name="$(ticket_name "$t")"
    v="$dir/verdicts/${name}-code.md"
    check_verdict  "$v" "G3 $name"
    check_recorded "$v" "G3 $name"
    check_brief    "$v" "G3 $name" reviewer "$feature" "$name"
    check_model    "$v" "G3 $name" factory-reviewer
    marker="$(ticket_marker "$feature" "$name")"
    if [ -n "$marker" ] && [ -f "$v" ] && [ "$(verdict_field "$v" Commit)" != "$marker" ]; then
      bad "G3 $name: verdict doesn't cover the latest integration (${marker:0:8})"
    fi
  done

  b="$dir/verdicts/behavior.md"
  check_verdict  "$b" "G4 behavior"
  check_recorded "$b" "G4 behavior"
  check_brief    "$b" "G4 behavior" validator "$feature" -
  check_model    "$b" "G4 behavior" factory-validator
  check_evidence "$b" "G4 behavior" "$spec"
  check_fresh    "$b" "G4 behavior" behavior
}

check_light() {                         # <verdict file>
  local f="$1" slug
  slug="$(printf '%s' "$f" | awk -F/ '{print $3}')"
  check_verdict  "$f" "light $slug"
  check_recorded "$f" "light $slug"
  check_brief    "$f" "light $slug" light-reviewer "$slug" -
  check_fresh    "$f" "light $slug"
}

mode="${1:-}"
case "$mode" in
  mission)
    check_mission "${2:?usage: gate.sh mission <feature>}"
    ;;

  mr)
    base="${2:?usage: gate.sh mr <base-ref>}"

    if [[ ",${CI_MERGE_REQUEST_LABELS:-}," == *",factory:bypass,"* ]]; then
      echo "WARNING: factory:bypass label set. Gates skipped; this is visible in the MR and counted."
      exit 0
    fi

    changed="$(git diff --name-only "$base"...HEAD)"

    # D23: the instrument can grow freely; changing or deleting a case
    # needs a contract amendment in the same MR.
    shrunk="$(git diff --name-status "$base"...HEAD -- "$FACTORY_INSTRUMENT_DIR/scenarios" \
      | awk '$1 !~ /^A/' || true)"
    if [ -n "$shrunk" ]; then
      echo "Instrument cases changed or removed:"
      printf '%s\n' "$shrunk" | sed 's/^/    /'
      if grep -qE '^\+.*\*\*(Amended|Withdrawn):\*\*' <<<"$(git diff "$base"...HEAD -- "$FACTORY_DIR")"; then
        ok "instrument change backed by a contract amendment"
      else
        bad "instrument weakened without a contract amendment (/contract amend)"
      fi
    fi

    code_changed="$(printf '%s\n' "$changed" \
      | grep -vE "^(${FACTORY_DIR}|${FACTORY_INSTRUMENT_DIR})/" \
      | grep -vE "$FACTORY_DOCS_RE" | grep -v '^$' || true)"

    if [ -z "$code_changed" ]; then
      echo "Planning, docs or instrument-only change: no lane gate applies."
      [ "$fail" -ne 0 ] && { echo; echo "FACTORY GATE: FAIL"; exit 1; }
      echo; echo "FACTORY GATE: PASS"
      exit 0
    fi

    behavior_changed=""
    if [ -f "$FACTORY_BEHAVIOR_PATHS_FILE" ]; then
      patterns="$(grep -vE '^[[:space:]]*(#|$)' "$FACTORY_BEHAVIOR_PATHS_FILE" || true)"
      if [ -n "$patterns" ]; then
        behavior_changed="$(printf '%s\n' "$code_changed" | grep -E -f <(printf '%s\n' "$patterns") || true)"
      fi
    fi

    missions="$(printf '%s\n' "$changed" \
      | awk -F/ -v d="$FACTORY_DIR" '$1 == d && $2 != "light" && NF > 2 { print $2 }' | sort -u)"

    lights="$(printf '%s\n' "$changed" | grep -E "^${FACTORY_DIR}/light/[^/]+/verdicts/code\.md$" || true)"

    if [ -n "$behavior_changed" ]; then
      echo "Lane: FULL (behavior paths changed)"
      printf '%s\n' "$behavior_changed" | sed 's/^/    /'
      if [ -z "$missions" ]; then
        bad "behavior changed but no mission is part of this MR (.${FACTORY_DIR#.}/<feature>/)"
      fi
    elif [ -n "$missions" ]; then
      echo "Lane: FULL (mission included in MR)"
    else
      echo "Lane: LIGHT"
      if [ -z "$lights" ]; then
        bad "light lane needs a fresh code review verdict: ${FACTORY_DIR}/light/<slug>/verdicts/code.md"
      fi
    fi
    # Fix-lane reviews count in either lane (D41).
    for f in $lights; do check_light "$f"; done

    for m in $missions; do check_mission "$m"; done
    ;;

  *)
    die "usage: gate.sh mission <feature> | gate.sh mr <base-ref>"
    ;;
esac

echo
if [ "$fail" -ne 0 ]; then echo "FACTORY GATE: FAIL"; exit 1; fi
echo "FACTORY GATE: PASS"
