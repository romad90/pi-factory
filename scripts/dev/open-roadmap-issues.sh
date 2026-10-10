#!/usr/bin/env bash
# Creates one GitHub issue per open roadmap item (docs/ROADMAP.md), with a
# milestone per release. Skips items whose title already exists. Needs gh.
#
# Usage: scripts/dev/open-roadmap-issues.sh [--dry-run]
set -euo pipefail
cd "$(dirname "$0")/../.."
dry=0; [ "${1:-}" = "--dry-run" ] && dry=1
command -v gh >/dev/null || { echo "gh not found"; exit 2; }

existing="$(gh issue list --state all --limit 500 --json title --jq '.[].title' 2>/dev/null || true)"
awk -F'|' '
  /^## v1\.0\.x/ { m = "v1.0.x" } /^## v1\.1\.0/ { m = "v1.1.0" } /^## v1\.2\.0/ { m = "v1.2.0" }
  /^## (v1\.0\.0|Explicitly)/ { m = "" }
  m != "" && $2 ~ /^ *[CFSX][0-9]+ *$/ {
    gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $3); gsub(/^ +| +$/, "", $5); gsub(/^ +| +$/, "", $6); gsub(/^ +| +$/, "", $7)
    printf "%s\t%s: %s\t%s\t%s\t%s\n", m, $2, $3, $5, $6, $7
  }' docs/ROADMAP.md |
while IFS=$'\t' read -r milestone title why fix effort; do
  if grep -qxF "$title" <<<"$existing"; then echo "exists: $title"; continue; fi
  body="$(printf '**Why:** %s\n\n**Fix:** %s\n\n**Effort:** %s\n\nFrom [docs/ROADMAP.md](../blob/develop/docs/ROADMAP.md).' "$why" "$fix" "$effort")"
  if [ "$dry" -eq 1 ]; then echo "[$milestone] $title"; continue; fi
  gh api "repos/{owner}/{repo}/milestones" -f title="$milestone" >/dev/null 2>&1 || true
  gh issue create --title "$title" --body "$body" --milestone "$milestone" >/dev/null
  echo "created: [$milestone] $title"
done
