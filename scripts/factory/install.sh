#!/usr/bin/env bash
# D139 (P31): a dependency mission's install, run by the factory before the
# contract, so the contract author and the workers work on the new version.
# Workers still never install (D65, D100): this script, not an agent, runs
# the npm commands the spec names under "## Dependencies" (in backticks), with
# install scripts off, then commits the manifest and lockfile on the mission
# branch and records the commit as kind "deps" (D124), by "factory (auto)".
#
# Usage: scripts/factory/install.sh <mission>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: install.sh <mission>}"
require_mission "$feature"
dir="$(mission_dir "$feature")"; spec="$dir/spec.md"
cmds="$(install_commands "$spec")"
[ -n "$cmds" ] || die "no npm install command in backticks under \"## Dependencies\" in $spec"
if grep -q $'\tdeps\t' "$dir/decisions.tsv" 2>/dev/null; then echo "Dependencies already changed and recorded (decisions.tsv): nothing to install."; exit 0; fi
dirty="$(git status --porcelain | cut -c4- | grep -E "$DEPS_FILES_RE" || true)"
[ -z "$dirty" ] || die "uncommitted changes to $(paste -sd' ' <<<"$dirty"): commit or discard them first"

# Only what the spec names: npm's save flags and name@version, nothing a shell
# would read. The spec is a person's (or a trigger's) words, never an agent's.
while IFS= read -r c; do
  read -ra a <<<"$c"
  for w in "${a[@]:2}"; do
    case "$w" in -D|--save-dev|-E|--save-exact|-O|--save-optional|-P|--save-prod|--save-peer) continue ;; esac
    [[ "$w" =~ ^(@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*@[A-Za-z0-9.^~*+-]+$ ]] \
      || die "\"$w\" in \`$c\` is not name@version or a save flag: the factory installs only named versions"
  done
done <<<"$cmds"
while IFS= read -r c; do
  read -ra a <<<"$c"
  echo "+ $c --ignore-scripts"
  npm "${a[@]:1}" --ignore-scripts || die "\`$c\` failed: fix the command under ## Dependencies, or make the change by hand and record it (/factory-deps)"
done <<<"$cmds"
files="$(git status --porcelain --untracked-files=all | cut -c4- | grep -E "$DEPS_FILES_RE" || true)"
[ -n "$files" ] || die "the install changed no manifest or lockfile: is the version already there?"
git add -- $files
git commit -q --author="$FACTORY_AUTHOR" -m "build($feature): $(paste -sd';' <<<"$cmds" | sed 's/;/; /g')" -m "Factory-Script: install" -- $files
c="$(git rev-parse --short HEAD)"; list="$(paste -sd, <<<"$files" | sed 's/,/, /g')"
decision_log "$feature" - deps "Dependencies installed by the factory (D139)" "commit $c: $list — $(paste -sd';' <<<"$cmds" | sed 's/;/; /g') (--ignore-scripts)" mission "factory (auto)"
bash "$here/checkpoint.sh" "$feature" >/dev/null
echo "Installed and committed in $c ($list). Reviewers count these files as delivered (D124); test-on-base skips a base older than $c."
