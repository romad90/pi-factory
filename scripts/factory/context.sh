#!/usr/bin/env bash
# Context repos (D99, proposal P13): the other repos a mission must read to
# understand a bug that lives between services. A mission changes one repo;
# these are cloned into the factory's own folder (never the human's clones),
# recorded, and made read-only for the mission. What holds (D101): the files
# lose their write permission (chmod a-w), which stops any process running as
# a non-root user; root ignores file permissions. The factory guard refuses
# agents' writes there (write/edit tools, redirections, tee, sed -i, cp, mv,
# chmod, rm), any git subcommand but read-only ones, and running
# "context.sh release". Each clone's push URL is "no-push", so even a git push
# the guard missed has nowhere to go.
#
# Usage: scripts/factory/context.sh sync    <feature>   clone or update, record, lock
#        scripts/factory/context.sh release <feature>   give write permission back
#        scripts/factory/context.sh check   <feature>   exit 0 when the clones match the spec
#
# The spec lists them under "## Context repos":
#   - `../bot-sync-a` — pulls from the API every 5 minutes
#   - https://git.example/org/bot-b.git@develop — pushes on webhook
# A local path is relative to the project folder. Clones land in
# $FACTORY_CONTEXT_DIR/<name> (default .factory/context/), excluded from git;
# .scratch/<feature>/context.tsv records what the investigation read.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

cmd="${1:?usage: context.sh <sync|release|check> <feature>}"
feature="${2:?usage: context.sh <sync|release|check> <feature>}"
require_mission "$feature"
dir="$(mission_dir "$feature")"; spec="$dir/spec.md"; tsv="$dir/context.tsv"
repos="$(context_repos "$spec")"
[ -n "$repos" ] || die "no '## Context repos' in $spec"
cdir="$FACTORY_CONTEXT_DIR"
# "home" names this project in briefs and questions (D99): never a context repo.
if cut -f1 <<<"$repos" | grep -qx home; then die "a context repo can't be named 'home' (reserved for this project): rename it in the spec"; fi

is_url() { [[ "$1" == *"://"* || "$1" =~ ^[^/[:space:]]+@[^:/[:space:]]+: ]]; }

case "$cmd" in
  check)
    [ -f "$tsv" ] || { echo "context: not synced yet ($tsv missing)"; exit 1; }
    # D101: name, source and branch, not names alone: a spec now pointing a
    # name at another repo or branch needs a new sync.
    want="$(awk -F'\t' '{ print $1 "\t" $2 "\t" ($3 == "" ? "default" : $3) }' <<<"$repos" | sort)"
    have="$(awk -F'\t' 'NR > 1 { print $1 "\t" $2 "\t" $3 }' "$tsv" | sort)"
    [ "$want" = "$have" ] || { echo "context: the spec lists $(tr '\t\n' '@ ' <<<"$want")but $tsv has $(tr '\t\n' '@ ' <<<"$have"): sync again"; exit 1; }
    while IFS=$'\t' read -r name _; do
      [ -d "$cdir/$name/.git" ] || { echo "context: $cdir/$name is missing: sync again"; exit 1; }
    done <<<"$repos"
    echo "context: in sync ($(wc -l <<<"$repos" | tr -d ' ') repo(s))"
    ;;

  sync)
    mkdir -p "$cdir"
    # Never part of a commit, a patch or a status: excluded for the whole repo.
    exclude="$(git rev-parse --git-path info/exclude)"; mkdir -p "$(dirname "$exclude")"
    prefix="$(project_prefix)"; pat="/${prefix:+$prefix/}$cdir/"
    grep -qxF "$pat" "$exclude" 2>/dev/null || printf '%s\n' "$pat" >> "$exclude"
    out="$(mktemp)"; trap 'rm -f "$out"' EXIT
    printf 'name\tsource\tbranch\tcommit\tsynced\n' > "$out"
    while IFS= read -r line; do
      # Split on tabs by hand: read would merge the empty branch field away.
      name="${line%%$'\t'*}"; rest="${line#*$'\t'}"; src="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"; br="${rest%%$'\t'*}"
      from="$src"
      if ! is_url "$src"; then
        [ -d "$src" ] || die "context repo $name: no folder at $src (relative to $PWD)"
        from="$(cd "$src" && pwd)"
      fi
      dest="$cdir/$name"
      if [ -d "$dest/.git" ]; then
        chmod -R u+w "$dest"
        git -C "$dest" fetch -q "$from" "${br:-HEAD}" || die "context repo $name: fetch from $src failed"
        git -C "$dest" checkout -q --detach FETCH_HEAD
        git -C "$dest" clean -qfdx
      else
        rm -rf "$dest"
        git clone -q ${br:+--branch "$br"} "$from" "$dest" || die "context repo $name: clone of $src failed"
      fi
      commit="$(git -C "$dest" rev-parse HEAD)"
      # D101: nothing is ever pushed from a context clone.
      if git -C "$dest" remote get-url origin >/dev/null 2>&1; then git -C "$dest" remote set-url --push origin no-push; fi
      chmod -R a-w "$dest"
      printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$src" "${br:-default}" "$commit" "$(date '+%F %H:%M')" >> "$out"
      echo "context: $name at ${commit:0:12} (read-only)"
    done <<<"$repos"
    cp "$out" "$tsv"
    bash "$here/checkpoint.sh" "$feature" >/dev/null
    ;;

  release)
    while IFS=$'\t' read -r name _; do
      [ -d "$cdir/$name" ] && chmod -R u+w "$cdir/$name" && echo "context: $name writable again"
    done <<<"$repos"
    ;;

  *) die "usage: context.sh <sync|release|check> <feature>" ;;
esac
