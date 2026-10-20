#!/usr/bin/env bash
# The worker's own gate (D66): the checks integrate.sh will run, in the
# worker's worktree, before it hands over. A worker that finishes on a red
# self-check costs a whole round; one that fixes it here costs a few turns.
#
# Runs, in order, stopping at the first failure:
#   1. the patch guard on the worker's change (frozen paths, silenced checks,
#      skipped or deleted tests, links, secrets), the hook's links left out;
#   2. lint, failing only on errors new against the baseline (D62);
#   3. tests; 4. the extra check (.factory/commands.env).
# Changes nothing: the change is read through a temporary index.
# Each run also saves the change as a draft patch in the repository's shared
# git folder (D73), so a wave that times out or a worktree that pi-subagents
# removes doesn't lose the work: locate-patch.sh falls back to it.
#
# Usage: scripts/factory/self-check.sh <feature>     (from the worktree)
# Prints SELF-CHECK: PASS, or SELF-CHECK: FAIL <check> and the end of its
# output. Exit 0 pass, 1 fail.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: self-check.sh <feature>}"
[ -f "$(mission_dir "$feature")/spec.md" ] || die "no mission '$feature' here ($(mission_dir "$feature")/spec.md)"
load_commands
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
lines="${FACTORY_SELF_CHECK_LINES:-40}"

status() {                             # D78: what the worker's last self-check said
  [ -n "${draft:-}" ] && printf '%s %s\n' "$1" "$(date '+%F %H:%M')" > "$draft.status" || true
}
fail() {                               # <check> <output file>
  status "FAIL $1"
  echo "SELF-CHECK: FAIL $1"
  tail -n "$lines" "$2"
  echo "Fix the code and run scripts/factory/self-check.sh $feature again. Never silence the check."
  exit 1
}

# 1. Patch guard on the change against HEAD, new files included, without
#    touching the worktree's own index.
skip=(); while IFS= read -r x; do skip+=("$x"); done < <(hook_excludes)
idx="$tmp/index"; cp "$(git rev-parse --git-path index)" "$idx"   # keeps sparse-checkout bits: the hidden instrument is not a deletion
GIT_INDEX_FILE="$idx" git add -A -- . "${skip[@]}" ":(exclude)${FACTORY_DIR}"
GIT_INDEX_FILE="$idx" git diff --cached --binary --relative HEAD -- . > "$tmp/change.patch"
draft=""
if ticket="$(worker_ticket "$feature")"; then draft="$(draft_patch "$feature" "$ticket")"; mkdir -p "$(dirname "$draft")"; fi
if [ ! -s "$tmp/change.patch" ]; then
  status "FAIL change"; echo "SELF-CHECK: FAIL change"; echo "No change against HEAD: nothing to hand over."; exit 1
fi
# D73: the draft keeps root-relative paths, like a patch rebuilt from a worktree.
if [ -n "$draft" ]; then
  GIT_INDEX_FILE="$idx" git diff --cached --binary HEAD -- . > "$draft.tmp" && mv "$draft.tmp" "$draft"
fi
bash "$here/patch-guard.sh" "$tmp/change.patch" --mission "$feature" > "$tmp/guard.out" 2>&1 || fail guard "$tmp/guard.out"

# 2. Lint, new errors only.
if [ -n "$FACTORY_LINT_CMD" ]; then
  run_lint "$tmp/lint.out" 2>/dev/null || fail lint "$tmp/lint.out"
fi

# 3–4. Tests and the extra check.
for check in tests extra; do
  cmd="$FACTORY_TEST_CMD"; [ "$check" = extra ] && cmd="$FACTORY_EXTRA_CMD"
  [ -n "$cmd" ] || continue
  bash -c "$cmd" > "$tmp/$check.out" 2>&1 || fail "$check" "$tmp/$check.out"
done

status PASS
echo "SELF-CHECK: PASS (guard, lint, tests${FACTORY_EXTRA_CMD:+, extra}; $(grep -c '^diff --git' "$tmp/change.patch") files changed)"
