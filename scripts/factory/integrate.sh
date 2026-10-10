#!/usr/bin/env bash
# Deterministic gate between a worker and its reviewer (D34):
# apply the worker's patch, run lint, tests and the extra check, commit only
# if green. Reviewers therefore only ever review committed, green code.
#
# Usage: scripts/factory/integrate.sh <feature> <ticket> <patch-file>
#   The patch path comes from the build wave's result ("patch" field), or
#   from scripts/factory/locate-patch.sh when the wave couldn't return it.
# Commands come from .factory/commands.env. Without FACTORY_TEST_CMD this
# refuses to run (D44): an integration without tests proves nothing.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: integrate.sh <feature> <ticket> <patch-file>}"
ticket="${2:?usage: integrate.sh <feature> <ticket> <patch-file>}"
patch="${3:?usage: integrate.sh <feature> <ticket> <patch-file>}"
dir="$(mission_dir "$feature")"
[ -f "$dir/issues/$ticket.md" ] || die "unknown ticket $ticket in $dir/issues"
[ -s "$patch" ] || die "patch $patch is missing or empty: record it with scripts/factory/record-no-patch.sh $feature $ticket"

load_commands
[ -n "$FACTORY_TEST_CMD" ] || [ "${FACTORY_ALLOW_NO_TESTS:-0}" = "1" ] \
  || die "FACTORY_TEST_CMD is empty in .factory/commands.env: refusing to integrate without tests (D44)"

dirty="$(git status --porcelain --untracked-files=no -- . ":(exclude)${FACTORY_DIR}")"
[ -z "$dirty" ] || die "working tree has changes outside ${FACTORY_DIR}/; commit or stash them first"

# D51: nothing unsafe lands, whatever the agent did in its worktree. A block
# is a failed round with the reasons, so the next build sees them.
if ! guard_out="$(bash "$here/patch-guard.sh" "$patch")"; then
  write_fail_verdict "$feature" "$ticket" patch-guard \
    "The patch was blocked by the patch guard: $(printf '%s' "$guard_out" | tr '\n' ';' | sed 's/;$//')"
  bash "$here/checkpoint.sh" "$feature" >/dev/null
  printf '%s\n' "$guard_out"
  echo "  ✗ patch blocked; recorded as a failed round in $dir/verdicts/$ticket-code.md"
  exit 1
fi

if ! git apply --check --index "$patch" 2>/dev/null; then
  if ! git apply --check --3way --index "$patch" 2>/dev/null; then
    write_fail_verdict "$feature" "$ticket" integrate \
      "The worker's patch does not apply on $(git rev-parse --short HEAD). Rebuild from the current code."
    bash "$here/checkpoint.sh" "$feature" >/dev/null
    echo "  ✗ patch does not apply; recorded as a failed round in $dir/verdicts/$ticket-code.md"
    exit 1
  fi
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
if run_check lint "$FACTORY_LINT_CMD" && run_check tests "$FACTORY_TEST_CMD" \
   && run_check extra "$FACTORY_EXTRA_CMD"; then
  type="feat"; [[ "$ticket" == *-fix-* ]] && type="fix"
  git commit -q -m "${FACTORY_COMMIT_TYPE:-$type}($feature): $ticket" \
    -m "Integrated by the factory after lint and tests passed." -- . ":(exclude)${FACTORY_DIR}"
  git rev-parse HEAD > "$dir/state/$ticket.integrated"
  bash "$here/checkpoint.sh" "$feature" >/dev/null
  echo "  ✓ committed $(git rev-parse --short "$(cat "$dir/state/$ticket.integrated")"); ready for review"
else
  git apply -R --index "$patch"
  # The failure is a round like any review FAIL, so escalation is automatic (D38).
  write_fail_verdict "$feature" "$ticket" integrate \
    "Lint, tests or the extra check failed when integrating the worker's patch. Log: $log"
  bash "$here/checkpoint.sh" "$feature" >/dev/null
  echo "  ✗ checks failed; patch reverted. Recorded in $dir/verdicts/$ticket-code.md (log: $log)"
  exit 1
fi
