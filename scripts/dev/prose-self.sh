#!/usr/bin/env bash
# The factory's own text under its plain-writing rules (D111): the briefs,
# the docs agents read, and the step messages next.sh prints. A ratchet:
# tests fail when the count rises above tests/prose-baseline.txt; when it
# falls, lower the baseline in the same commit.
#
# Usage: scripts/dev/prose-self.sh [--count]
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$root"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# Each NEXT message, one line each, as the person reads it (variables kept as names).
grep -ohE '\bstep [a-z-]+ "[^"]+"' scripts/factory/next.sh | sed -E 's/^step [a-z-]+ "//; s/"$//' > "$tmp/next-messages.md"
found="$(node scripts/factory/prose-lint.mjs .factory/briefs/*.md docs/agents/*.md "$tmp/next-messages.md" || true)"
found="${found//$tmp\//}"
if [ "${1:-}" = --count ]; then [ -z "$found" ] && echo 0 || wc -l <<<"$found" | tr -d ' '; exit 0; fi
printf '%s\n' "$found"
