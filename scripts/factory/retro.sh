#!/usr/bin/env bash
# The mission's retro, built from its record and kept private.
#
# Usage: scripts/factory/retro.sh pack <mission>   the raw record, as Markdown, on stdout
#        scripts/factory/retro.sh save <mission>   copy .scratch/<mission>/retro.md to this
#                                                  machine's data folder, outside every repository
#
# Why: a retro written by the lead from its own session sees only that session
# (mission 4 on a real project: the retro covered the last day, missed the
# first two). The pack is what every session left behind: metrics, decisions,
# rounds per ticket, amendments, guard refusals, provider errors, request sizes.
#
# Where retros go: ${FACTORY_DATA_DIR:-~/.pi-factory/data}/<repo>[-<project>]/retros/<mission>.md,
# next to the mission's data pack (D103). Never the factory's own folder: it is a
# public repository's mirror. `factory learn` reads them from there.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

cmd="${1:?usage: retro.sh pack|save <mission>}"; feature="${2:?usage: retro.sh pack|save <mission>}"
dir="$(mission_dir "$feature")"
[ -f "$dir/spec.md" ] || die "no mission '$feature'"

data_dir() {
  local repo prefix
  prefix="$(project_prefix)"
  repo="$(basename "$(git rev-parse --show-toplevel)")${prefix:+-${prefix//\//-}}"
  printf '%s/%s' "${FACTORY_DATA_DIR:-$HOME/.pi-factory/data}" "$repo"
}

case "$cmd" in
  pack)
    bash "$here/archive.sh" collect "$feature" >/dev/null 2>&1 || true
    echo "# Raw record: $feature"
    echo
    echo "Built by scripts/factory/retro.sh from what every session left behind. Cite these lines as evidence."
    echo
    echo "## Metrics"
    bash "$here/metrics.sh" "$feature" 2>/dev/null | sed -n '/^|/p' || echo "(metrics unavailable)"
    echo
    echo "## Tickets: verdicts and rounds"
    echo '```'
    bash "$here/next.sh" "$feature" 2>/dev/null | sed -n '/round [0-9]/p' || true
    echo '```'
    echo
    echo "## Human decisions (decisions.tsv: date, ticket, kind, question, answer)"
    if [ -f "$dir/decisions.tsv" ]; then
      awk -F'\t' 'NR > 1 { q = substr($4, 1, 160); a = substr($5, 1, 200); printf "- %s %s %s: %s → %s\n", $1, $2, $3, q, a }' "$dir/decisions.tsv"
    else echo "- none"; fi
    echo
    echo "## Contract amendments and withdrawals"
    grep -n -E '^\s*- \*\*(Amended|Withdrawn):\*\*' "$dir/spec.md" | sed 's/^/- /' || echo "- none"
    echo
    echo "## Pauses and provider errors"
    git log --format='%ad %s' --date=format:'%F %R' -- "$dir" 2>/dev/null | grep -i -E 'paus|provider|429|rate limit' | head -20 | sed 's/^/- /' || true
    { [ -d "$dir/state" ] && grep -rh -i -E 'provider|429|rate limit' "$dir/state" 2>/dev/null | head -10 | sed 's/^/- /'; } || true
    echo
    echo "## Guard refusals, by rule (archive)"
    arch="$(dirname "$(dirname "$(dirname "$(draft_patch "$feature" x)")")")/archive/$feature"
    if [ -d "$arch" ]; then
      node -e '
        const fs = require("fs"), path = require("path"), n = {};
        for (const d of fs.readdirSync(process.argv[1])) {
          try { for (const g of JSON.parse(fs.readFileSync(path.join(process.argv[1], d, "run.json"), "utf8")).guard || []) n[g.rule] = (n[g.rule] || 0) + 1; } catch {}
        }
        const e = Object.entries(n).sort((a, b) => b[1] - a[1]);
        console.log(e.length ? e.map(([r, c]) => `- ${r}: ${c}`).join("\n") : "- none");' "$arch"
    else echo "- no archive"; fi
    echo
    echo "## Request sizes (factory tokens)"
    echo '```'
    node "$here/tokens.mjs" "$arch" --top 8 2>/dev/null | head -40 || echo "(no archive)"
    echo '```'
    echo
    echo "## Journals (what fix rounds tried)"
    ls "$dir/journal" 2>/dev/null | sed 's/^/- /' || echo "- none"
    ;;
  save)
    src="$dir/retro.md"
    [ -s "$src" ] || die "no $src: write the retro first (/skill:mission-retro)"
    out="$(data_dir)/retros"; mkdir -p "$out"
    cp "$src" "$out/$feature.md"
    bash "$here/metrics.sh" "$feature" --json > "$out/$feature.metrics.json" 2>/dev/null || rm -f "$out/$feature.metrics.json"
    echo "retro: saved to $out/$feature.md (private: outside every repository; factory learn reads it)"
    ;;
  *) die "usage: retro.sh pack|save <mission>" ;;
esac
