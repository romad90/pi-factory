#!/usr/bin/env bash
# Plain-writing findings for a mission (D111): what prose-lint.mjs finds in
# the text people and agents read (spec, strategy, critiques, verdicts, MR
# description), by docs/agents/writing.md. A warning: next.sh shows the
# count, this prints them. FACTORY_PROSE=off skips it. Blocking waits for a
# job's numbers to show it pays (fewer ambiguity findings, fewer split verdicts).
# It writes nothing: a file here would dirty the checkout between steps.
#
# Usage: scripts/factory/prose.sh <mission> [--count]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"
feature="${1:?usage: prose.sh <mission> [--count]}"; mode="${2:-}"
found=""
if [ "${FACTORY_PROSE:-warn}" != off ] && dir="$(mission_dir "$feature")" && [ -d "$dir" ]; then
  shopt -s nullglob
  files=()
  for f in "$dir/spec.md" "$dir/strategy.md" "$dir/pr.md" "$dir"/verdicts/*.md "$dir"/*critique*.md; do [ -f "$f" ] && files+=("$f"); done
  g=(); [ ! -f GLOSSARY.md ] || g=(--glossary GLOSSARY.md)
  [ ${#files[@]} -eq 0 ] || found="$(node "$here/prose-lint.mjs" "${g[@]}" "${files[@]}" || true)"
fi
if [ "$mode" = --count ]; then [ -z "$found" ] && echo 0 || wc -l <<<"$found" | tr -d ' '; exit 0; fi
[ -z "$found" ] && echo "prose: nothing to report" || printf '%s\n' "$found"
