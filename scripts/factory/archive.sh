#!/usr/bin/env bash
# The run archive (D97, P14): every factory run keeps what it did, outside
# the project's MRs. Transcripts are the factory's most valuable data: they are
# what scoring reads and what improvements are judged on.
#
# Usage:
#   scripts/factory/archive.sh collect <feature>       archive the runs not archived yet
#   scripts/factory/archive.sh list <feature>          one line per archived run
#   scripts/factory/archive.sh export <feature> [file] pack a mission's archive (tar.gz)
#   scripts/factory/archive.sh import <file>           unpack an export into this checkout's archive
#   scripts/factory/archive.sh tokens <feature> [--budget N]  request sizes per run, and the tool results that fill them (P20)
#
# Where: <git-common-dir>/pi-factory/archive/<feature>/<run>/, next to the
# draft patches (D73) and run logs (D91): never committed, never in an MR,
# outliving worktrees. Each run keeps:
#   run.json        run id, agent, model, thinking, usage, duration, brief id,
#                   ticket, outcome (verdict result and file, integrated commit)
#   brief.md        what the agent was asked (pi-subagents' _input.md)
#   output.md       what it answered
#   transcript.jsonl its tool calls and messages
# run.json also lists the command guard's refusals during the run (from the
# shared guard.log, by time window): the audit trail of what an agent tried
# and was not allowed to run, next to what it did run (the transcript).
# Text is redacted with the patch guard's secret patterns before it is kept.
# Runs come from pi-subagents' per-run artifacts ({run}_{agent}_meta.json and
# its siblings), found where usage.sh looks (FACTORY_USAGE_DIRS), newer than
# the mission's spec. Best effort: nothing found, nothing archived.
# Only this checkout's runs (D101): a run counts when its meta file or a path
# it records is under the checkout (top level, a git worktree, the git common
# dir, where the benchmark's worktrees live), or when its brief id is one the
# mission recorded. Another clone's or another user's runs in a shared temp
# folder are ignored.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

usage="usage: archive.sh collect|list|export|tokens <feature> [file|--budget N] | import <file>"
cmd="${1:?$usage}"; shift

archive_root() {                       # <git-common-dir>/pi-factory/archive
  printf '%s/archive\n' "$(dirname "$(dirname "$(dirname "$(draft_patch x x)")")")"
}

case "$cmd" in
  collect)
    feature="${1:?$usage}"; dir="$(mission_dir "$feature")"
    [ -f "$dir/spec.md" ] || die "no mission '$feature'"
    out="$(archive_root)/$feature"; mkdir -p "$out"
    read -r -a roots <<<"${FACTORY_USAGE_DIRS:-.pi/subagents $HOME/.pi/agent ${TMPDIR:-/tmp}}"
    existing=()
    for r in "${roots[@]}"; do [ -d "$r" ] && existing+=("$r"); done
    [ ${#existing[@]} -gt 0 ] || { echo "archive: nothing to collect"; exit 0; }
    owned=("$(git rev-parse --show-toplevel)" "$(git rev-parse --path-format=absolute --git-common-dir)" "$PWD")
    while IFS= read -r w; do owned+=("$w"); done < <(git worktree list --porcelain | sed -n 's/^worktree //p')
    find "${existing[@]}" -maxdepth 7 -type f -name '*_meta.json' -newer "$dir/spec.md" 2>/dev/null \
      | node "$here/archive.mjs" collect "$out" "$dir" "$(git rev-parse HEAD 2>/dev/null || echo none)" "$(dirname "$(archive_root)")/guard.log" "${owned[@]}"
    ;;
  list)
    feature="${1:?$usage}"
    node "$here/archive.mjs" list "$(archive_root)/$feature"
    ;;
  tokens)
    # P20: where the mission's tokens go. Collects first, so the newest runs count.
    feature="${1:?$usage}"; shift
    bash "$here/archive.sh" collect "$feature" >/dev/null 2>&1 || true
    node "$here/tokens.mjs" "$(archive_root)/$feature" "$@"
    ;;
  export)
    feature="${1:?$usage}"; src="$(archive_root)/$feature"
    [ -d "$src" ] || die "no archive for '$feature' yet: run archive.sh collect $feature"
    file="${2:-$PWD/archive-$feature-$(date +%Y%m%d).tar.gz}"
    tar -czf "$file" -C "$(archive_root)" "$feature"
    echo "archive: $(find "$src" -name run.json | wc -l | tr -d ' ') run(s) exported to $file"
    ;;
  import)
    file="${1:?$usage}"; [ -f "$file" ] || die "no file $file"
    # Only plain relative paths: an archive never writes outside the archive folder.
    if tar -tzf "$file" | grep -qE '(^/|(^|/)\.\.(/|$))'; then die "$file holds paths outside the archive"; fi
    root="$(archive_root)"; mkdir -p "$root"
    tar -xzf "$file" -C "$root" --no-same-owner
    echo "archive: imported into $root"
    ;;
  *) die "$usage" ;;
esac
