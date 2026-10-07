#!/usr/bin/env bash
# Commits a mission's state (spec, tickets, verdicts, logs) so worker
# worktrees, which branch from HEAD, can read it. Mission files never make a
# verdict stale (D10), so checkpointing is always safe.
#
# Usage: scripts/factory/checkpoint.sh <feature>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: checkpoint.sh <feature>}"
dir="$(mission_dir "$feature")"
[ -d "$dir" ] || die "no mission at $dir"
git add -- "$dir"
if git diff --cached --quiet -- "$dir"; then
  echo "Mission state already committed."
else
  git commit -q -m "factory($feature): mission state" -- "$dir"
  echo "Committed mission state: $(git rev-parse --short HEAD)"
fi
