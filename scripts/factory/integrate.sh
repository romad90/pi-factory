#!/usr/bin/env bash
# Deterministic gate between a worker and its reviewer (D34):
# apply the worker's patch, run lint and tests, commit only if green.
# Reviewers therefore only ever review committed, green code.
#
# Usage: scripts/factory/integrate.sh <feature> <ticket> <patch-file>
#   The patch path comes from the worker's result (artifactPaths / handoff
#   manifest of its pi-subagents worktree run).
# Commands come from .factory/commands.env (FACTORY_LINT_CMD, FACTORY_TEST_CMD).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: integrate.sh <feature> <ticket> <patch-file>}"
ticket="${2:?usage: integrate.sh <feature> <ticket> <patch-file>}"
patch="${3:?usage: integrate.sh <feature> <ticket> <patch-file>}"
dir="$(mission_dir "$feature")"
[ -f "$dir/issues/$ticket.md" ] || die "unknown ticket $ticket in $dir/issues"
[ -s "$patch" ] || die "patch $patch is missing or empty (did the worker change anything?)"

# shellcheck source=/dev/null
[ -f .factory/commands.env ] && . .factory/commands.env
FACTORY_LINT_CMD="${FACTORY_LINT_CMD:-}"; FACTORY_TEST_CMD="${FACTORY_TEST_CMD:-}"

dirty="$(git status --porcelain --untracked-files=no -- . ":(exclude)${FACTORY_DIR}")"
[ -z "$dirty" ] || die "working tree has changes outside ${FACTORY_DIR}/; commit or stash them first"

if git apply --check --index "$patch" 2>/dev/null; then :; else
  git apply --check --3way --index "$patch" || die "patch does not apply on $(git rev-parse --short HEAD); rebuild the ticket"
fi

if grep -qE "^diff --git a/${FACTORY_INSTRUMENT_DIR}/" "$patch"; then
  die "patch touches ${FACTORY_INSTRUMENT_DIR}/: workers must not see or change the instrument (D21)"
fi

git apply --3way --index "$patch"

mkdir -p "$dir/logs" "$dir/state"
log="$dir/logs/$ticket-integrate.log"
: > "$log"
run_check() {                # <label> <command>
  [ -n "$2" ] || { echo "  - $1: not configured (.factory/commands.env)" | tee -a "$log"; return 0; }
  echo "  - $1: $2" | tee -a "$log"
  bash -c "$2" >>"$log" 2>&1
}

echo "Integrating $ticket on $(git rev-parse --short HEAD)"
if run_check lint "$FACTORY_LINT_CMD" && run_check tests "$FACTORY_TEST_CMD"; then
  git commit -q -m "factory($feature): integrate $ticket"
  git rev-parse HEAD > "$dir/state/$ticket.integrated"
  echo "  ✓ committed $(git rev-parse --short HEAD); ready for review"
else
  git apply -R --index "$patch"
  # Record the failure as a verdict so the worker's fix round sees it and the
  # round counts toward escalation. Commit = current marker (or HEAD when the
  # ticket was never integrated), so the ticket returns to "build", not "review".
  v="$dir/verdicts/$ticket-code.md"; mkdir -p "$dir/verdicts"
  prev="$(verdict_round "$v")"; marker="$(ticket_marker "$feature" "$ticket")"
  cat > "$v" <<VERDICT
# Verdict: $ticket — round $(( ${prev:-0} + 1 ))
**Result:** FAIL
**Commit:** ${marker:-$(git rev-parse HEAD)}
**Model:** none (integrate.sh)
**Brief:** integrate

## Issues
- [blocking] Lint or tests failed when integrating the worker's patch. Log: $log
VERDICT
  echo "  ✗ checks failed; patch reverted. Failure recorded in $v (log: $log)"
  exit 1
fi
