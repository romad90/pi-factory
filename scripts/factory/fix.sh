#!/usr/bin/env bash
# Fix lane (D41): small changes without a mission. Smallest change by a
# human (or the main session), then deterministic checks, a blast-radius
# check, and one fresh reviewer from another family (the light lane).
#
# Usage:
#   fix.sh start <slug> <what...> [--mission <feature>]   record the request and base
#   fix.sh check <slug>                                   blast radius + lint/tests
#   then: scripts/factory/workflow.sh light <slug> <base>, collect.sh --light <slug>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

cmd="${1:?usage: fix.sh <start|check> <slug> ...}"
slug="${2:?usage: fix.sh $cmd <slug> ...}"; shift 2
dir="$FACTORY_DIR/light/$slug"; req="$dir/request.md"

case "$cmd" in
  start)
    mission=""; what=()
    while [ $# -gt 0 ]; do
      case "$1" in --mission) mission="${2:?--mission needs a feature}"; shift 2 ;; *) what+=("$1"); shift ;; esac
    done
    [ ${#what[@]} -gt 0 ] || die "say what to fix"
    [ -f "$req" ] && die "fix $slug already started ($req)"
    mkdir -p "$dir"
    printf '# Fix: %s\n**Base:** %s\n**Started:** %s\n**Mission:** %s\n\n%s\n' \
      "$slug" "$(git rev-parse HEAD)" "$(date +%F)" "${mission:--}" "${what[*]}" > "$req"
    if [ -n "$mission" ]; then
      decision_log "$mission" - fix "Fix lane: $slug" "${what[*]}" fix
      bash "$here/checkpoint.sh" "$mission" >/dev/null
    fi
    bash "$here/checkpoint.sh" --light "$slug" >/dev/null
    echo "Fix $slug started at $(git rev-parse --short HEAD)."
    echo "Make the smallest change, commit it (Conventional Commit), then: /factory-fix $slug check"
    ;;

  check)
    [ -f "$req" ] || die "no fix $slug (fix.sh start first)"
    base="$(verdict_field "$req" Base)"
    files="$(git diff --name-only "$base" HEAD -- . ":(exclude)${FACTORY_DIR}")"
    [ -n "$files" ] || die "no committed change since $base: commit the fix first"
    lines="$(git diff --numstat "$base" HEAD -- . ":(exclude)${FACTORY_DIR}" | awk '{ n += $1 + $2 } END { print n + 0 }')"
    patterns="$(behavior_patterns)"
    behavior=""
    [ -n "$patterns" ] && behavior="$(printf '%s\n' "$files" | grep -E -f <(printf '%s\n' "$patterns") || true)"
    instrument="$(printf '%s\n' "$files" | grep -E "^${FACTORY_INSTRUMENT_DIR}/" || true)"
    blocked=""
    [ -n "$behavior" ] && blocked="changes behavior paths ($(printf '%s' "$behavior" | paste -sd' ' -)): that needs a mission or a fix ticket"
    [ -n "$instrument" ] && blocked="touches the instrument: that needs a contract amendment"
    [ "$lines" -gt "$FACTORY_FIX_MAX_LINES" ] && blocked="${blocked:+$blocked; }$lines lines changed (fix lane limit: $FACTORY_FIX_MAX_LINES)"
    {
      echo "# Blast radius: $slug"
      echo "**Base:** $base"; echo "**Head:** $(git rev-parse HEAD)"
      echo "**Lines changed:** $lines"; echo "**Result:** ${blocked:+BLOCKED}${blocked:-OK}"
      echo; echo "## Files"; printf -- '- %s\n' $files
      [ -n "$blocked" ] && { echo; echo "## Why blocked"; echo "$blocked"; }
    } > "$dir/blast-radius.md"
    cat "$dir/blast-radius.md"
    # D51: the same safety rules as for agents, except protected paths
    # (changing CI or the factory may be the point of a human fix).
    git diff "$base" HEAD -- . ":(exclude)${FACTORY_DIR}" > "$dir/change.patch"
    if ! guard_out="$(bash "$here/patch-guard.sh" "$dir/change.patch" --human)"; then
      blocked="${blocked:+$blocked; }$(printf '%s' "$guard_out" | tr '\n' ';' | sed 's/;$//')"
      { echo; echo "## Patch guard"; printf '%s\n' "$guard_out"; } >> "$dir/blast-radius.md"
      sed -i.bak 's/^\*\*Result:\*\* OK$/**Result:** BLOCKED/' "$dir/blast-radius.md" && rm -f "$dir/blast-radius.md.bak"
      printf '%s\n' "$guard_out"
    fi
    if [ -n "$blocked" ]; then bash "$here/checkpoint.sh" --light "$slug" >/dev/null; exit 1; fi

    load_commands
    echo; echo "Checks"
    for pair in "lint|$FACTORY_LINT_CMD" "tests|$FACTORY_TEST_CMD" "extra|$FACTORY_EXTRA_CMD"; do
      label="${pair%%|*}"; c="${pair#*|}"
      [ -n "$c" ] || { echo "  - $label: not configured"; continue; }
      if bash -c "$c" > "$dir/$label.log" 2>&1; then echo "  ✓ $label"
      else echo "  ✗ $label (log: $dir/$label.log)"; bash "$here/checkpoint.sh" --light "$slug" >/dev/null; exit 1; fi
    done
    bash "$here/checkpoint.sh" --light "$slug" >/dev/null
    echo; echo "NEXT → scripts/factory/workflow.sh light $slug $base"
    ;;

  *) die "unknown command: $cmd" ;;
esac
