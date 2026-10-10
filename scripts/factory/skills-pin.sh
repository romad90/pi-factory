#!/usr/bin/env bash
# Enforces the pinned mattpocock/skills version (D36).
#
# Usage:
#   scripts/factory/skills-pin.sh verify        CI + local: files match the pin, nothing shadows them
#   scripts/factory/skills-pin.sh check-global  local only: warn about machine-wide copies that differ
#   scripts/factory/skills-pin.sh update        after a deliberate upgrade: rewrite the manifest
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

pin=.factory/skills-pin
list="$pin/upstream.txt"
manifest="$pin/skills.sha256"
required_version="v1.3.1"

skills() { grep -vE '^[[:space:]]*(#|$)' "$list"; }
hash_tree() {               # stable manifest of every pinned upstream file
  local s
  for s in $(skills); do
    find "$FACTORY_SKILLS_DIR/$s" -type f | LC_ALL=C sort
  done | while IFS= read -r f; do sha256 "$f"; done
}

fail=0
ok()  { printf '  ✓ %s\n' "$*"; }
bad() { printf '  ✗ %s\n' "$*"; fail=1; }

case "${1:-verify}" in
  verify)
    echo "Skills pin ($required_version)"
    if grep -q "^\*\*Version:\*\* $required_version\$" "$pin/UPSTREAM.md"; then ok "UPSTREAM.md declares $required_version"
    else bad "UPSTREAM.md must declare **Version:** $required_version"; fi
    for s in $(skills); do
      [ -f "$FACTORY_SKILLS_DIR/$s/SKILL.md" ] || bad "missing pinned skill: $FACTORY_SKILLS_DIR/$s"
    done
    if diff -q <(hash_tree) "$manifest" >/dev/null 2>&1; then
      ok "$(skills | wc -l | tr -d ' ') upstream skills match the manifest"
    else
      bad "upstream skill files differ from the pinned manifest:"
      diff <(hash_tree) "$manifest" | sed 's/^/      /' | awk 'NR <= 20'
    fi
    # Shadowing: other project locations a harness could load first or instead.
    for s in $(skills); do
      for alt in ".agents/skills/$s" ".claude/skills/$s" ".opencode/skill/$s"; do
        [ -e "$alt" ] && bad "shadow copy of $s at $alt (remove it; $FACTORY_SKILLS_DIR is the only copy)"
      done
    done
    # pi-subagents also scans legacy .agents/**/*.md for agent definitions;
    # any markdown there would register as an agent.
    if [ -d .agents ] && [ -n "$(find .agents -name '*.md' -print -quit)" ]; then
      bad ".agents/ contains markdown files, which pi-subagents would load as agents"
    else
      ok "no stray agent definitions under .agents/"
    fi
    ;;

  check-global)
    echo "Machine-wide skill copies (affect the main Pi session, not factory subagents)"
    found=0
    for s in $(skills); do
      want="$(sha256 "$FACTORY_SKILLS_DIR/$s/SKILL.md" | cut -d' ' -f1)"
      for root in "$HOME/.pi/agent/skills" "$HOME/.agents/skills" "$HOME/.pi/skills"; do
        g="$root/$s/SKILL.md"
        [ -f "$g" ] || continue
        found=1
        have="$(sha256 "$g" | cut -d' ' -f1)"
        if [ "$have" = "$want" ]; then ok "$g matches the pin"
        else printf '  ! %s differs from the pinned %s (remove it or upgrade deliberately)\n' "$g" "$required_version"; fi
      done
    done
    [ "$found" -eq 0 ] && ok "no machine-wide copies"
    exit 0
    ;;

  update)
    hash_tree > "$manifest"
    echo "Manifest rewritten: $manifest ($(wc -l < "$manifest" | tr -d ' ') files). Commit it with the upgraded skills and update UPSTREAM.md."
    exit 0
    ;;

  *) die "usage: skills-pin.sh verify|check-global|update" ;;
esac

[ "$fail" -eq 0 ] || { echo "SKILLS PIN: FAIL"; exit 1; }
echo "SKILLS PIN: PASS"
