#!/usr/bin/env bash
# The test-on-base check (D96) on its own, for scripts outside integration
# (the benchmark, a human checking a patch). Integration and self-check call
# the same function in lib.sh.
#
# Usage: scripts/factory/test-on-base.sh <mission> <ticket> <patch> [base]
#   patch: project-relative, as integration sees it; base: default HEAD.
# Exit: 0 as expected or not checked (the line says which), 1 mismatch
# (the reason on stdout), 2 error or inconclusive (the tests don't apply on
# the base, no temporary worktree, the test command can't start, the base is
# already red; D101). The test output goes to the mission's logs.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

usage="usage: test-on-base.sh <mission> <ticket> <patch> [base]"
feature="${1:-}"; ticket="${2:-}"; patch="${3:-}"; base="${4:-HEAD}"
if [ -z "$feature" ] || [ -z "$ticket" ] || [ -z "$patch" ]; then echo "$usage" >&2; exit 2; fi
[ -s "$patch" ] || { echo "factory: no patch at $patch" >&2; exit 2; }
dir="$(mission_dir "$feature")"
[ -f "$dir/spec.md" ] || { echo "factory: no mission '$feature'" >&2; exit 2; }
git rev-parse --verify -q "$base^{commit}" >/dev/null || { echo "factory: unknown base $base" >&2; exit 2; }
load_commands
mkdir -p "$dir/logs"
rc=0; line="$(test_on_base "$feature" "$ticket" "$patch" "$dir/logs/$ticket-test-on-base.log" "$base")" || rc=$?
echo "$line"; exit "$rc"
