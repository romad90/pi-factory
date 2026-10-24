#!/usr/bin/env bash
# Deterministic gate between a worker and its reviewer (D34):
# apply the worker's patch, run lint (new errors only, D62), tests and the
# extra check, commit only if green. Reviewers therefore only ever review committed, green code.
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
require_mission "$feature"
ticket="${2:?usage: integrate.sh <feature> <ticket> <patch-file>}"
patch="${3:?usage: integrate.sh <feature> <ticket> <patch-file>}"
# D60: the wave returned no path; look for the patch here instead of
# relying on the lead to run locate-patch.sh first.
if [ "$patch" = null ]; then patch="$(bash "$here/locate-patch.sh" "$feature" "$ticket" 2>/dev/null || true)"; fi
dir="$(mission_dir "$feature")"
[ -f "$dir/issues/$ticket.md" ] || die "unknown ticket $ticket in $dir/issues"
[ -s "$patch" ] || die "patch $patch is missing or empty: record it with scripts/factory/record-no-patch.sh $feature $ticket"

load_commands
[ -n "$FACTORY_TEST_CMD" ] || [ "${FACTORY_ALLOW_NO_TESTS:-0}" = "1" ] \
  || die "FACTORY_TEST_CMD is empty in .factory/commands.env: refusing to integrate without tests (D44)"

dirty="$(git status --porcelain --untracked-files=no -- . ":(exclude)${FACTORY_DIR}")"
[ -z "$dirty" ] || die "working tree has changes outside ${FACTORY_DIR}/; commit or stash them first"

# D56: in a monorepo, every patch is made relative to the project first; a
# patch that reaches outside the project is blocked like any unsafe patch.
raw_patch="$patch"; patch="$(mktemp)"; hookless="$(mktemp)"; trap 'rm -f "$patch" "$hookless"' EXIT
# D87: the hook's dependency links and .env.factory are never part of a
# change; a captured patch that still has them loses them here, not a round.
if ! node "$here/patch-paths.mjs" strip-hook "$raw_patch" "$hookless" "${FACTORY_DEPS_LINKS:-node_modules .venv}" 2>"$hookless.log"; then
  cp "$raw_patch" "$hookless"          # unreadable patch: the guard below decides, as before D87
fi
sed 's/^/  /' "$hookless.log" >&2; rm -f "$hookless.log"
if ! project_patch "$hookless" "$patch"; then
  write_fail_verdict "$feature" "$ticket" patch-guard \
    "The patch was blocked by the patch guard: paths: it changes files outside the project $(project_prefix)/"
  bash "$here/checkpoint.sh" "$feature" >/dev/null
  echo "  ✗ patch touches files outside the project; recorded as a failed round in $dir/verdicts/$ticket-code.md"
  exit 1
fi

# D51: nothing unsafe lands, whatever the agent did in its worktree. A block
# is a failed round with the reasons, so the next build sees them.
if ! guard_out="$(bash "$here/patch-guard.sh" "$patch" --mission "$feature")"; then
  write_fail_verdict "$feature" "$ticket" patch-guard \
    "The patch was blocked by the patch guard: $(printf '%s' "$guard_out" | tr '\n' ';' | sed 's/;$//')"
  bash "$here/checkpoint.sh" "$feature" >/dev/null
  printf '%s\n' "$guard_out"
  echo "  ✗ patch blocked; recorded as a failed round in $dir/verdicts/$ticket-code.md"
  exit 1
fi

# D96: new tests must disagree with the code before the change the way the
# mission's intent says: fail there (feature, bugfix) or pass there
# (maintenance, refactor). Checked before anything is applied here.
mkdir -p "$dir/logs"
if ! tob="$(test_on_base "$feature" "$ticket" "$patch" "$dir/logs/$ticket-test-on-base.log")"; then
  write_fail_verdict "$feature" "$ticket" test-on-base \
    "${tob#test on base: } (the tests alone, run on $(git rev-parse --short HEAD): $dir/logs/$ticket-test-on-base.log)"
  bash "$here/checkpoint.sh" "$feature" >/dev/null
  echo "  ✗ $tob; recorded as a failed round in $dir/verdicts/$ticket-code.md"
  exit 1
fi
echo "  - $tob"
case "$tob" in "test on base: skipped by the ticket ("*)   # the opt-out is a decision: recorded once
  why="${tob#test on base: skipped by the ticket (}"; why="${why%)}"
  grep -qF "$(printf '%s\ttest-on-base' "$ticket")" "$dir/decisions.tsv" 2>/dev/null \
    || decision_log "$feature" "$ticket" test-on-base "Skip the test-on-base check (D96)?" "Yes: $why" ticket "issue file" ;;
esac
if ! project_apply --check --index "$patch" 2>/dev/null; then
  if ! project_apply --check --3way --index "$patch" 2>/dev/null; then
    write_fail_verdict "$feature" "$ticket" integrate \
      "The worker's patch does not apply on $(git rev-parse --short HEAD). Rebuild from the current code."
    bash "$here/checkpoint.sh" "$feature" >/dev/null
    echo "  ✗ patch does not apply; recorded as a failed round in $dir/verdicts/$ticket-code.md"
    exit 1
  fi
fi
# D80: a 3-way apply can still conflict (two tickets of a wave changed the
# same lines). Never leave a conflicted tree: put the touched paths back as
# HEAD has them and record a failed round, so the ticket rebuilds on HEAD.
if ! project_apply --3way --index "$patch" > "$(mktemp)" 2>&1; then
  root="$(git rev-parse --show-toplevel)"
  conflicted="$(git -C "$root" diff --name-only --diff-filter=U)"
  touched="$(git -C "$root" diff --cached --name-only HEAD; printf '%s\n' "$conflicted")"
  printf '%s\n' "$touched" | sort -u | while IFS= read -r f; do
    [ -n "$f" ] || continue
    if git -C "$root" cat-file -e "HEAD:$f" 2>/dev/null; then git -C "$root" checkout -q HEAD -- "$f"
    else git -C "$root" rm -q -f --cached -- "$f" 2>/dev/null || true; rm -f -- "$root/$f"; fi
  done
  write_fail_verdict "$feature" "$ticket" integrate \
    "The worker's patch conflicts with code integrated since it started ($(printf '%s' "$conflicted" | paste -sd' ' -)). Rebuild from the current code ($(git rev-parse --short HEAD)); keep the tests already there."
  bash "$here/checkpoint.sh" "$feature" >/dev/null
  echo "  ✗ patch conflicts with the current code; tree restored, recorded as a failed round in $dir/verdicts/$ticket-code.md"
  exit 1
fi
# The patch is already in this branch (a wave salvaged after its ticket was
# integrated, or the same change landed another way): nothing to check or commit.
if git diff --cached --quiet HEAD -- .; then
  echo "  = the patch changes nothing on $(git rev-parse --short HEAD): its change is already in this branch. Nothing integrated, no round recorded."
  exit 3
fi

mkdir -p "$dir/logs" "$dir/state"
log="$dir/logs/$ticket-integrate.log"
: > "$log"
run_check() {                # <label> <command>
  [ -n "$2" ] || { echo "  - $1: not configured (.factory/commands.env)" | tee -a "$log"; return 0; }
  echo "  - $1: $2" | tee -a "$log"
  bash -c "$2" >>"$log" 2>&1
}

lint_fail=""
check_lint() {                # D62: only errors new against the baseline fail
  [ -n "$FACTORY_LINT_CMD" ] || { echo "  - lint: not configured (.factory/commands.env)" | tee -a "$log"; return 0; }
  echo "  - lint: $FACTORY_LINT_CMD (new errors only, vs $FACTORY_LINT_BASELINE)" | tee -a "$log"
  local out rc=0; out="$(mktemp)"; run_lint "$out" 2>/dev/null || rc=1
  [ "$rc" -eq 0 ] || lint_fail="$(sed -n '/^lint: new errors/,$p' "$out" | sed -n '2,6p' | sed 's/^ *//' | paste -sd ';' -)"
  cat "$out" >> "$log"; rm -f "$out"; return "$rc"
}

echo "Integrating $ticket on $(git rev-parse --short HEAD)"
if check_lint && run_check tests "$FACTORY_TEST_CMD" \
   && run_check extra "$FACTORY_EXTRA_CMD"; then
  type="feat"; [[ "$ticket" == *-fix-* ]] && type="fix"
  git commit -q -m "${FACTORY_COMMIT_TYPE:-$type}($feature): $ticket" \
    -m "Integrated by the factory after lint and tests passed." -m "Factory-Script: integrate" -- . ":(exclude)${FACTORY_DIR}"
  git rev-parse HEAD > "$dir/state/$ticket.integrated"
  bash "$here/checkpoint.sh" "$feature" >/dev/null
  journal_collect "$feature" "$ticket" "integrated $(git rev-parse --short HEAD)"   # D84
  rm -f "$(draft_patch "$feature" "$ticket")" "$(draft_patch "$feature" "$ticket").status"   # D73: the draft is spent
  bash "$here/usage.sh" "$feature" >/dev/null 2>&1 || true   # D85
  bash "$here/archive.sh" collect "$feature" >/dev/null 2>&1 || true   # D97
  echo "  ✓ committed $(git rev-parse --short "$(cat "$dir/state/$ticket.integrated")"); ready for review"
else
  project_apply -R --index "$patch"
  # D78: say whether the worker checked its own work before handing it over.
  sc="$(cat "$(draft_patch "$feature" "$ticket").status" 2>/dev/null || true)"
  sc="${sc:-never run}"
  # D84: a round that fails exactly like the one before made no progress:
  # the ticket escalates now instead of spending another round.
  mkdir -p "$dir/state"; sig="$(failure_signature "$log")"; stuck=""
  if [ -n "$sig" ] && [ -f "$dir/state/$ticket.signature" ] && [ "$sig" = "$(cat "$dir/state/$ticket.signature")" ]; then
    stuck=". No progress: the same failures as the previous round; escalated to the human"
    date '+%F %H:%M' > "$dir/state/$ticket.stuck"
  fi
  [ -n "$sig" ] && printf '%s\n' "$sig" > "$dir/state/$ticket.signature"
  # The failure is a round like any review FAIL, so escalation is automatic (D38).
  write_fail_verdict "$feature" "$ticket" integrate \
    "Lint, tests or the extra check failed when integrating the worker's patch. Log: $log${lint_fail:+. New lint errors (fix them, never silence them): $lint_fail}. The worker's last self-check: $sc. Run scripts/factory/self-check.sh $feature until it prints SELF-CHECK: PASS before handing over$stuck."
  bash "$here/checkpoint.sh" "$feature" >/dev/null
  echo "  ✗ checks failed; patch reverted. Recorded in $dir/verdicts/$ticket-code.md (log: $log)"
  exit 1
fi
