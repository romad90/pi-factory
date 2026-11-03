#!/usr/bin/env bash
# The mission's retro, built from its record and kept private.
#
# Usage: scripts/factory/retro.sh pack <mission>   the raw record, as Markdown, on stdout
#        scripts/factory/retro.sh save <mission>   copy .scratch/<mission>/retro.md to this
#                                                  machine's data folder, outside every repository
#        scripts/factory/retro.sh close <mission>  after the merge: the MR's review comments as
#                                                  candidate misses to label, reverts of the merged
#                                                  change, escaped defects (P23); run it again to update
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

cmd="${1:?usage: retro.sh pack|save|close <mission>}"; feature="${2:?usage: retro.sh pack|save|close <mission>}"
dir="$(mission_dir "$feature")"
[ -f "$dir/spec.md" ] || die "no mission '$feature'"

data_dir() {
  local repo prefix
  prefix="$(project_prefix)"
  repo="$(repo_name)${prefix:+-${prefix//\//-}}"
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
    echo "## Frictions (failed, repeated and refused tool calls, from the transcripts)"
    echo '```'
    node "$here/frictions.mjs" "$arch" --top 8 2>/dev/null | head -40 || echo "(no archive)"
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
  close)
    # P23: what the factory's gates could not see, once the team has reviewed and merged.
    saved="$(data_dir)/retros/$feature.md"
    [ -s "$saved" ] || die "no saved retro at $saved: retro.sh save $feature first"
    url="${FACTORY_MR_URL:-$(head -1 "$dir/mr.url" 2>/dev/null || true)}"
    [ -n "$url" ] || die "no MR for $feature: $dir/mr.url is missing (mr.sh writes it; or set FACTORY_MR_URL)"
    re='^https?://([^/]+)/(.+)/-/merge_requests/([0-9]+)'
    [[ "$url" =~ $re ]] || die "not a GitLab MR URL: $url"
    host="${BASH_REMATCH[1]}"; path="${BASH_REMATCH[2]}"; iid="${BASH_REMATCH[3]}"
    enc="$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$path")"
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    ep="projects/$enc/merge_requests/$iid"
    if command -v glab >/dev/null 2>&1 && glab auth status >/dev/null 2>&1; then
      glab api "$ep" > "$tmp/mr.json" 2>/dev/null || true
      glab api "$ep/notes?per_page=100&sort=asc" > "$tmp/notes.json" 2>/dev/null || true
    else
      tf="${FACTORY_GITLAB_TOKEN_FILE:-$HOME/.pi-factory/gitlab-token}"; token="${GITLAB_TOKEN:-}"
      if [ -z "$token" ] && [ -f "$tf" ] && [ -z "$(find "$tf" -perm /077 2>/dev/null)" ]; then token="$(tr -d '[:space:]' < "$tf")"; fi
      [ -n "$token" ] || die "no way to read the MR: log in with glab, or put a token in $tf (mode 600)"
      api="${FACTORY_GITLAB_API:-https://$host/api/v4}"
      TOKEN="$token" node -e '
        const [base, out] = process.argv.slice(1), h = { "PRIVATE-TOKEN": process.env.TOKEN };
        (async () => { for (const [p, f] of [["", "mr.json"], ["/notes?per_page=100&sort=asc", "notes.json"]]) {
          const r = await fetch(base + p, { headers: h }); if (!r.ok) { console.error(`GitLab ${r.status}`); process.exit(1); }
          require("fs").writeFileSync(out + "/" + f, await r.text()); } })().catch((e) => { console.error(e.message); process.exit(1); });' \
        "${api%/}/$ep" "$tmp" || die "could not read $url from the GitLab API"
    fi
    [ -s "$tmp/mr.json" ] || die "could not read $url"
    # Reverts: commits whose message says they revert the merged change (merge or squash commit).
    shas="$(node -e 'try{const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log([m.merge_commit_sha,m.squash_commit_sha,m.sha].filter(Boolean).join(" "))}catch{}' "$tmp/mr.json")"
    git fetch -q origin 2>/dev/null || true
    : > "$tmp/reverts.tsv"
    for s in $shas; do
      git log --all --format='%H%x09%s' --grep="This reverts commit $s" 2>/dev/null | awk -v s="$s" '{ print $0 "\t" s }' >> "$tmp/reverts.tsv" || true
    done
    node "$here/retro-close.mjs" "$saved" "$tmp/mr.json" "$tmp/notes.json" "$tmp/reverts.tsv" "${FACTORY_MR_BOT_USERS:-}"
    echo "Label each review comment [miss] or [ok], and add escaped defects, in $saved"
    ;;
  *) die "usage: retro.sh pack|save|close <mission>" ;;
esac
