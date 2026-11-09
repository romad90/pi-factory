#!/usr/bin/env bash
# G2 — contract ↔ tickets coverage, the mechanical direction.
# (Spec → contract traceability is a judgement call: /contract-critic.)
#
# Usage: scripts/factory/coverage.sh <feature>
# Exit:  0 = no violations, 1 = violations, 2 = missing inputs
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: coverage.sh <feature>}"
dir="$(mission_dir "$feature")"
spec="$dir/spec.md"

[ -f "$spec" ] || die "no spec at $spec"
ids="$(contract_ids "$spec")"
[ -n "$ids" ] || die "no active assertions in the contract of $spec"

shopt -s nullglob
tickets=("$dir"/issues/*.md)
[ ${#tickets[@]} -gt 0 ] || die "no tickets in $dir/issues"

violations=0
declare -A cover=() qb=()

for t in "${tickets[@]}"; do
  name="$(ticket_name "$t")"
  covers="$(ticket_covers "$t")"

  # P3: a path the ticket names exists here, or the ticket says the change
  # creates it (new, create, add, rename on its line). deps-node-22's writer
  # stated a test file under lib/ that never existed.
  while IFS= read -r line; do
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      p="${p#./}"
      [ -e "$p" ] && continue
      case "$p" in "$FACTORY_DIR"/*) continue ;; esac              # mission records, written as the mission runs
      git check-ignore -q -- "$p" 2>/dev/null && continue          # outputs (coverage/, .tap/): generated, never committed
      grep -qiwE '(new|creates?|created|creating|adds?|added|renames?|renamed|generates?|generated|writes?|written)' <<<"$line" && continue
      echo "VIOLATION  $name: names \`$p\`, which does not exist here; check it, or say the change creates it"
      violations=$((violations + 1))
    done < <(grep -oE '`[A-Za-z0-9_.][A-Za-z0-9_./-]*/[A-Za-z0-9_.-]+\.[A-Za-z0-9]+`' <<<"$line" | tr -d '`')
  done < <(sed '/^## Covers/,$d' "$t")

  if [ -z "$covers" ]; then
    echo "VIOLATION  $name: no '## Covers' section, or it lists no assertion"
    violations=$((violations + 1)); continue
  fi

  if [ "$covers" = "enabler" ]; then
    if [ -z "$(ticket_enabler_reason "$t")" ]; then
      echo "VIOLATION  $name: enabler without a sentence naming what it unblocks"
      violations=$((violations + 1))
    fi
    continue
  fi

  for id in $covers; do
    # E38: a health-fix ticket covers the quality-bar item its finding names.
    if [[ "$id" == QB-* ]]; then
      if grep -q -- "$id" docs/agents/quality-bar.md 2>/dev/null; then qb[$id]="${qb[$id]:-}${qb[$id]:+, }$name"
      else echo "VIOLATION  $name: cites $id, which is not in docs/agents/quality-bar.md"; violations=$((violations + 1)); fi
      continue
    fi
    if ! grep -qx "$id" <<<"$ids"; then
      echo "VIOLATION  $name: cites $id, which is unknown or withdrawn"
      violations=$((violations + 1)); continue
    fi
    cover[$id]="${cover[$id]:-}${cover[$id]:+, }$name"
  done
done

echo
echo "Assertion → tickets"
for id in "${!qb[@]}"; do printf '  %-18s %s (quality bar)\n' "$id" "${qb[$id]}"; done
for id in $ids; do
  if [ -n "${cover[$id]:-}" ]; then
    printf '  %-18s %s\n' "$id" "${cover[$id]}"
  else
    printf '  %-18s UNCOVERED\n' "$id"
    violations=$((violations + 1))
  fi
done

echo
if [ "$violations" -gt 0 ]; then
  echo "G2: $violations violation(s)"
  exit 1
fi
echo "G2: pass"
