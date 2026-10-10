#!/usr/bin/env bash
# Commits a mission's state (spec, tickets, verdicts, logs, decisions) so
# worker worktrees, which branch from HEAD, can read it. Mission files never
# make a verdict stale (D10), so checkpointing is always safe. The factory's
# scripts call it themselves after every change they make (D46); you rarely
# need to run it by hand.
#
# Usage: scripts/factory/checkpoint.sh <feature>
#        scripts/factory/checkpoint.sh --light <slug>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

if [ "${1:-}" = "--light" ]; then
  name="${2:?usage: checkpoint.sh --light <slug>}"; dir="$FACTORY_DIR/light/$name"
else
  name="${1:?usage: checkpoint.sh <feature> | --light <slug>}"; dir="$(mission_dir "$name")"
fi
[ -d "$dir" ] || die "nothing at $dir"
git add -- "$dir"
if git diff --cached --quiet -- "$dir"; then
  echo "State already committed."
else
  git commit -q -m "chore(factory): $name state" -- "$dir"
  echo "Committed state: $(git rev-parse --short HEAD)"
fi
