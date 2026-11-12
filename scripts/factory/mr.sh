#!/usr/bin/env bash
# Open (or update) the mission's merge request in one command (D86). The human
# runs it after /pr: opening the MR stays a human act, the typing goes away.
#
# Usage: scripts/factory/mr.sh <feature> [--draft] [--dry-run]
#        scripts/factory/mr.sh <feature> --local "<why>"   closed without an MR (F7)
#
# Body:   .scratch/<feature>/pr.md (what /pr writes), else /tmp/pr-body-<feature>.md
# Title:  the body's first "# " line (removed from the description), else
#         "<type>(<mission>): <the spec's title>", the type from its intent
#         (feature feat, bugfix fix, refactor refactor, maintenance test),
#         else the last commit's subject
# Target: $FACTORY_MR_TARGET (environment or .factory/commands.env), else the
#         remote's default branch, else the branch the mission came from (D116)
# Branch: the current one, pushed to origin. Refused when it is the target or
#         matches a pattern in $FACTORY_MR_BLOCKED_BRANCHES (space-separated
#         globs, e.g. "chore/*" where such branches deploy).
#
# Reviewer: $FACTORY_MR_REVIEWER, else the spec's **Reviewer:** line (a GitLab
#         username): the person who approved the contract and design (D95).
# How the MR is created, first that works:
#   0. origin on github.com: gh, if installed and logged in (gh pr create
#      --repo <origin's owner/name> --body-file, never another remote's
#      repository; draft with --draft; the reviewer is asked, best effort);
#      without gh, the branch is pushed and the steps to open the PR printed
#   1. glab, if installed and logged in
#   2. the GitLab API, with the token in the variable $FACTORY_GITLAB_TOKEN_ENV
#      names (default GITLAB_TOKEN; the name only, never the token), or in
#      ~/.pi-factory/gitlab-token (mode 600; FACTORY_GITLAB_TOKEN_FILE)
#      The MR is set to squash, and the description ends with "Also in this MR":
#      commits that aren't the mission's work, and how many files are its record.
#   3. push options (title and target set); the description is printed to paste
# Run it again after editing pr.md: an open MR for the branch gets the new body.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

warn() { printf 'factory: %s\n' "$*" >&2; }

case "${1:-}" in ""|-h|--help|help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; -*) die "unknown option $1 (mr.sh --help)" ;; esac
feature="${1}"; shift
draft=""; dry=""; local_why=""
while [ $# -gt 0 ]; do
  case "$1" in
    --draft) draft=1 ;;
    --dry-run) dry=1 ;;
    --local) local_why="${2:-}"; [ -n "$local_why" ] && [[ "$local_why" != --* ]] || die "--local needs a reason, e.g. --local \"private repository\""; shift ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done
dir="$(mission_dir "$feature")"
# F7: a mission closed without an MR (a private repository, work merged by
# hand) says so in mr.url, and next.sh stops asking for /pr.
if [ -n "$local_why" ]; then
  [ -d "$dir" ] || die "no mission $feature"
  printf 'local: %s (closed %s, no MR)\n' "$local_why" "$(date +%F)" > "$dir/mr.url"
  echo "$feature closed locally: $local_why. next.sh now says closed; save the retro if it isn't (/skill:mission-retro)."
  exit 0
fi

conf() { # conf NAME: environment first, then .factory/commands.env
  local v="${!1:-}"
  if [ -z "$v" ] && [ -f .factory/commands.env ]; then
    v="$(sed -n "s/^[[:space:]]*\(export[[:space:]]*\)\{0,1\}$1=[\"']\{0,1\}\([^\"']*\).*/\2/p" .factory/commands.env | tail -1)"
  fi
  printf '%s' "$v"
}

body_file=""
for f in "$dir/pr.md" "/tmp/pr-body-$feature.md"; do [ -s "$f" ] && { body_file="$f"; break; }; done
[ -n "$body_file" ] || die "no PR body: run /pr first (it writes $dir/pr.md)"

branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" != HEAD ] || die "detached HEAD: check out the mission branch"
target="$(mr_target "$branch")"
[ -n "$target" ] || die "no target branch: set FACTORY_MR_TARGET in .factory/commands.env"
[ "$branch" != "$target" ] || die "you are on $target itself: check out the mission branch"
# D109: a job's mission goes on top of the previous mission's MR while that one
# is open (its branch is on the remote); merged with its branch deleted, GitLab
# moves this MR onto the target. Each MR then shows one mission's work.
job="$(spec_job "$dir/spec.md" || true)"; stacked=""
if [ -n "$job" ] && [ "$branch" = "$(job_branch "$job" "$feature")" ]; then
  prev="$(job_prev_mission "$job" "$feature" 2>/dev/null || true)"
  if [ -n "$prev" ] && [ -n "$(git ls-remote --heads origin "$(job_branch "$job" "$prev")" 2>/dev/null)" ]; then
    target="$(job_branch "$job" "$prev")"; stacked="$prev"
  fi
fi
remove_src=false; [ -z "$job" ] || [ "$branch" != "$(job_branch "$job" "$feature")" ] || remove_src=true
rm_flag=""; [ "$remove_src" = false ] || rm_flag=--remove-source-branch
for g in $(conf FACTORY_MR_BLOCKED_BRANCHES); do
  # shellcheck disable=SC2254
  case "$branch" in $g) die "branch $branch matches FACTORY_MR_BLOCKED_BRANCHES ($g): push it under another name" ;; esac
done

# D95: the reviewer who approved the plan reviews the MR (a GitLab username).
reviewer="$(conf FACTORY_MR_REVIEWER)"
[ -n "$reviewer" ] || reviewer="$(verdict_field "$dir/spec.md" Reviewer 2>/dev/null | sed 's/^@//; s/[[:space:]].*//' || true)"

title="$(sed -n 's/^# \{1,\}//p' "$body_file" | head -1)"
# No heading in the body: the mission's own title, never the last commit's
# subject (mission 6's MR was about to be called after a one-line fix).
if [ -z "$title" ] && [ -f "$dir/spec.md" ]; then
  h="$(sed -n 's/^# \{1,\}//p' "$dir/spec.md" | head -1 | sed -E 's/^([Ss]pec|[Mm]ission)[[:space:]]*(:|—|–|-)[[:space:]]*//')"
  case "$(verdict_field "$dir/spec.md" Intent)" in
    feature) ty=feat ;; bugfix) ty=fix ;; refactor) ty=refactor ;; maintenance) ty="test" ;; *) ty=chore ;;
  esac
  [ -z "$h" ] || title="$ty($feature): $h"
fi
[ -n "$title" ] || title="$(git log -1 --format=%s)"
case "$title" in *'[skip ci]'*|*'[ci skip]'*) die "the title would skip CI: $title" ;; esac
desc="$(mktemp)"; trap 'rm -f "$desc"' EXIT
awk 'done || !/^# /{print; next} {done=1}' "$body_file" | sed '/./,$!d' > "$desc"
# GitHub: the PR body says so where GitLab would set it (eslint-10 printed GitLab steps on GitHub).
github="$(github_repo)"
[ -n "$github" ] || [ -z "$draft" ] || title="Draft: $title"

# What else rides in this MR, said up front so nobody finds it after merging
# (mission 5: setup commits and ~150 mission-record files the reviewer wasn't told about).
also_in_mr() {
  local base others nscratch nfiles
  base="$(git merge-base HEAD "origin/$target" 2>/dev/null || git merge-base HEAD "$target" 2>/dev/null || true)"
  [ -n "$base" ] || return 0
  others="$(git log --no-merges --format='%H%x09%s' "$base..HEAD" | while IFS=$'\t' read -r h s; do
    git log -1 --format=%B "$h" | grep -q '^Factory-Script:' && continue
    case "$s" in *"($feature):"*) continue ;; esac
    printf -- '- %s %s\n' "${h:0:8}" "$s"
  done)"
  nfiles="$(git diff --name-only "$base" HEAD | grep -c . || true)"
  nscratch="$(git diff --name-only "$base" HEAD -- "$(mission_dir "$feature")" | grep -c . || true)"
  [ -n "$others" ] || [ "${nscratch:-0}" -gt 0 ] || return 0
  printf '\n## Also in this MR\n\n'
  [ -z "$others" ] || printf 'Commits that are not the mission'"'"'s work (setup, configuration), to review as such:\n%s\n\n' "$others"
  [ "${nscratch:-0}" -eq 0 ] || printf '%s of the %s changed files are the mission'"'"'s record under `%s/` (spec, contract, tickets, verdicts, decisions): the audit trail, not product code.\n' "$nscratch" "$nfiles" "$(mission_dir "$feature")"
  printf '\nMerge with **squash**%s: `develop` gets one commit; the detailed history stays here.\n' "$([ -n "$github" ] || echo ' (set on this MR)')"
}
also_in_mr >> "$desc" || true
if [ -n "$stacked" ]; then
  printf '\n## Builds on\n\nMission `%s` of job `%s` (%s): merge that MR first; this one then moves onto its target by itself.\n' \
    "$stacked" "$job" "$(cat "$(mission_dir "$stacked")/mr.url" 2>/dev/null || echo "its MR")" >> "$desc"
fi

[ -z "$(git status --porcelain --untracked-files=no)" ] || warn "uncommitted changes are not in the MR"
echo "MR: $branch → $target"
echo "    title: $title"
echo "    body:  $body_file"
[ -z "$reviewer" ] || echo "    reviewer: $reviewer"
if [ -n "$dry" ]; then echo "(dry run: nothing pushed)"; exit 0; fi

url_file="$dir/mr.url"
record() { [ -n "$1" ] || return 0; printf '%s\n' "$1" > "$url_file"; echo "MR: $1"; }
# D103: the mission's data, kept without anyone asking: the last runs go into
# the archive, the metrics next to them, and one export per mission lands in
# this machine's data folder (FACTORY_DATA_DIR, default ~/.pi-factory/data),
# outside every repository. Best effort: never a reason not to open the MR.
mission_data() {
  bash "$here/archive.sh" collect "$feature" >/dev/null 2>&1 || true
  local arch data repo prefix
  prefix="$(git rev-parse --show-prefix)"; prefix="${prefix%/}"
  arch="$(dirname "$(dirname "$(dirname "$(draft_patch "$feature" x)")")")/archive/$feature"
  mkdir -p "$arch" || return 0                 # no runs found: the metrics alone are still data
  bash "$here/metrics.sh" "$feature" --json > "$arch/metrics.json" 2>/dev/null || rm -f "$arch/metrics.json"
  repo="$(repo_name)${prefix:+-${prefix//\//-}}"
  data="${FACTORY_DATA_DIR:-$HOME/.pi-factory/data}/$repo"; mkdir -p "$data" || return 0
  bash "$here/archive.sh" export "$feature" "$data/$feature-$(date +%Y%m%d).tar.gz" 2>/dev/null | sed 's/^/  /' || true
}
mission_data

# 0. GitHub: gh, else the steps to open the PR by hand.
if [ -n "$github" ]; then
  git push -u origin "$branch"
  if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
    desc_keep="$(git rev-parse --path-format=absolute --git-common-dir)/pi-factory/mr-description-$feature.md"
    mkdir -p "$(dirname "$desc_keep")"; cp "$desc" "$desc_keep"     # outside the tree: never dirties it
    echo
    echo "origin is on GitHub and gh isn't installed or logged in (gh auth login). Open the PR with:"
    echo "    gh pr create --repo $github --base $target --head $branch --title \"$title\" --body-file \"$desc_keep\"${draft:+ --draft}"
    echo "or on github.com (compare $target...$branch), pasting the description from $desc_keep, then merge with squash."
    exit 0
  fi
  existing="$(gh pr list --repo "$github" --head "$branch" --base "$target" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)"
  if [ -n "$existing" ]; then
    gh pr edit "$existing" --repo "$github" --title "$title" --body-file "$desc" >/dev/null
    echo "updated PR #$existing"
  else
    out="$(gh pr create --repo "$github" --head "$branch" --base "$target" --title "$title" --body-file "$desc" ${draft:+--draft} 2>&1)" || die "gh: $out"
    existing="$(printf '%s\n' "$out" | grep -o 'https://[^ ]*/pull/[0-9]*' | head -1)"
    # D95's reviewer is a GitLab username: asked, never a reason to fail.
    [ -z "$reviewer" ] || gh pr edit "$existing" --repo "$github" --add-reviewer "$reviewer" >/dev/null 2>&1 || warn "could not ask $reviewer to review (not a GitHub user here?)"
  fi
  record "$(gh pr view "$existing" --repo "$github" --json url --jq .url 2>/dev/null || true)"
  exit 0
fi

# 1. glab
if command -v glab >/dev/null 2>&1 && glab auth status >/dev/null 2>&1; then
  git push -u origin "$branch"
  existing="$(glab mr list --source-branch "$branch" --target-branch "$target" -F json 2>/dev/null \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const a=JSON.parse(s);if(a[0])process.stdout.write(String(a[0].iid))}catch{}})' || true)"
  if [ -n "$existing" ]; then
    glab mr update "$existing" --title "$title" --description "$(cat "$desc")" >/dev/null
    record "$(glab mr view "$existing" -F json 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).web_url||"")}catch{}})' || true)"
    echo "updated MR !$existing"
  else
    out="$(glab mr create --source-branch "$branch" --target-branch "$target" --title "$title" \
      --description "$(cat "$desc")" ${reviewer:+--reviewer "$reviewer"} --squash-before-merge ${rm_flag:+"$rm_flag"} --yes 2>&1)" || die "glab: $out"
    record "$(printf '%s\n' "$out" | grep -o 'https://[^ ]*merge_requests/[0-9]*' | head -1)"
  fi
  exit 0
fi

# 2. GitLab API with a token
token_env="$(conf FACTORY_GITLAB_TOKEN_ENV)"; token_env="${token_env:-GITLAB_TOKEN}"
token="${!token_env:-}"
# Or a file only this user can read (never the shell history or a dotfile in a repo).
tf="${FACTORY_GITLAB_TOKEN_FILE:-$HOME/.pi-factory/gitlab-token}"
if [ -z "$token" ] && [ -f "$tf" ]; then
  if [ -n "$(find "$tf" -perm /077 2>/dev/null)" ]; then warn "$tf is readable by others: chmod 600 it; not used"
  else token="$(tr -d '[:space:]' < "$tf")"; fi
fi
if [ -n "$token" ]; then
  git push -u origin "$branch"
  remote="$(git remote get-url origin)"
  api="$(conf FACTORY_GITLAB_API)"
  # shellcheck disable=SC2016
  res="$(REMOVE_SRC="$remove_src" REVIEWER="$reviewer" TITLE="$title" SRC="$branch" TGT="$target" REMOTE="$remote" API="$api" TOKEN="$token" DESC_FILE="$desc" node -e '
const fs = require("fs"); const e = process.env;
const m = e.REMOTE.match(/^(?:https?:\/\/(?:[^@\/]+@)?([^\/]+)\/|(?:ssh:\/\/)?[^@]+@([^:\/]+)(?::\d+)?[:\/])(.+?)(?:\.git)?\/?$/);
if (!m) { console.log("ERR cannot read the project from the remote " + e.REMOTE.replace(/\/\/[^@]*@/, "//")); process.exit(0); }
const host = m[1] || m[2], path = m[3];
const base = (e.API || `https://${host}/api/v4`).replace(/\/$/, "") + "/projects/" + encodeURIComponent(path) + "/merge_requests";
const h = { "PRIVATE-TOKEN": e.TOKEN, "Content-Type": "application/json" };
const body = { source_branch: e.SRC, target_branch: e.TGT, title: e.TITLE, description: fs.readFileSync(e.DESC_FILE, "utf8"), remove_source_branch: e.REMOVE_SRC === "true", squash: true };
(async () => {
  const q = `${base}?state=opened&source_branch=${encodeURIComponent(e.SRC)}&target_branch=${encodeURIComponent(e.TGT)}`;
  let r = await fetch(q, { headers: h });
  if (!r.ok) { console.log(`ERR GitLab ${r.status} on ${base.replace(/\/merge_requests$/, "")}`); return; }
  const open = await r.json();
  if (e.REVIEWER && !open[0]) {        // D95: username → id; an unknown name is skipped, not fatal
    const u = await fetch(`${base.replace(/\/projects\/.*$/, "")}/users?username=${encodeURIComponent(e.REVIEWER)}`, { headers: h }).then(x => x.ok ? x.json() : []).catch(() => []);
    if (u[0]) body.reviewer_ids = [u[0].id];
  }
  r = open[0]
    ? await fetch(`${base}/${open[0].iid}`, { method: "PUT", headers: h, body: JSON.stringify({ title: body.title, description: body.description, squash: true }) })
    : await fetch(base, { method: "POST", headers: h, body: JSON.stringify(body) });
  const j = await r.json().catch(() => ({}));
  console.log(r.ok ? `OK ${open[0] ? "updated" : "created"} ${j.web_url || ""}` : `ERR GitLab ${r.status}: ${JSON.stringify(j.message || j.error || "")}`);
})().catch(err => console.log("ERR " + err.message));
')"
  case "$res" in
    OK*) echo "MR $(echo "$res" | awk '{print $2}')"; record "$(echo "$res" | awk '{print $3}')"; exit 0 ;;
    *) warn "${res#ERR }; falling back to push options" ;;
  esac
fi

# 3. push options: GitLab creates the MR; the description is pasted by hand
desc_keep="$(git rev-parse --path-format=absolute --git-common-dir)/pi-factory/mr-description-$feature.md"
mkdir -p "$(dirname "$desc_keep")"; cp "$desc" "$desc_keep"     # outside the tree: never dirties it
git push -u origin "$branch" -o merge_request.create -o "merge_request.target=$target" -o "merge_request.title=$title" ${rm_flag:+-o merge_request.remove_source_branch}
echo
echo "The push opened the MR (title and target set), but a push can't carry a multi-line description or squash."
echo "Paste the description from: $desc_keep   (and tick Squash commits)"
echo
echo "To never do this by hand again, once per machine: a GitLab access token with the api scope"
echo "(GitLab, Preferences, Access tokens), kept out of your shell history:"
echo "    install -m 600 /dev/null ~/.pi-factory/gitlab-token && \$EDITOR ~/.pi-factory/gitlab-token"
echo "then run mr.sh again: it finds an open MR for this branch and fills it (description, squash, reviewer)."
