#!/usr/bin/env bash
# Answers a worker's question when it is already settled (D70), so it never
# waits on a human: a rule of the factory, or the human's own earlier answer.
# Exact rules only, no model. Anything else, and anything that could be
# irreversible or about the contract, goes to the human.
#
# Usage: scripts/factory/resolve.sh <feature> <ticket|-> <question>
# Prints "<rule>\t<answer>" and exits 0 when settled; exits 1 otherwise.
# Called by human.sh ask; FACTORY_RESOLVER=0 turns it off.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

usage="usage: resolve.sh <feature> <ticket|-> <question>"
feature="${1:?$usage}"; ticket="${2:?$usage}"; question="${3:?$usage}"
dir="$(mission_dir "$feature")"
has() { grep -qEi -- "$1" <<<"$question"; }
answer() { printf '%s\t%s\n' "$1" "$2"; exit 0; }

# Never settled by a script: production, data, secrets, the contract itself (D47).
if has 'production|prod([^a-z]|$)|delete|drop |truncate|migrat|secret|credential|password|token|api[ _-]?key|contract|irreversib|deploy|publish|customer'; then
  exit 1
fi

norm() { tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]\n' ' ' | tr -s ' ' | sed 's/^ //; s/ $//'; }
want="$(printf '%s' "$question" | norm)"
# Asked again after an automatic answer: the rule didn't settle it, a human decides.
if [ -f "$dir/decisions.tsv" ] && awk -F'\t' -v t="$ticket" 'NR > 1 && $2 == t && $3 == "auto" { print $4 }' "$dir/decisions.tsv" \
     | while IFS= read -r q; do if [ "$(printf '%s' "$q" | norm)" = "$want" ]; then echo hit; fi; done | grep -q hit; then
  exit 1
fi

# 1. The human already answered this question in this mission.
if [ -f "$dir/decisions.tsv" ]; then
  prev="$(awk -F'\t' 'NR > 1 && ($3 == "decide") { print $4 "\t" $5 }' "$dir/decisions.tsv" \
    | while IFS=$'\t' read -r q a; do
        if [ "$(printf '%s' "$q" | norm)" = "$want" ]; then printf '%s\n' "$a"; fi
      done | tail -1)"
  [ -z "$prev" ] || answer earlier "$prev (the human's earlier answer to the same question)"
fi

# 2. Silencing a check.
if has 'eslint-disable|ts-ignore|ts-nocheck|ts-expect-error|noqa|nolint|type: ignore|\.(skip|only)([^a-z]|$)|skip(ping)? (the |this |these |a )?(failing |faulty |broken )?tests?|disable (the |this |a )?(lint|rule|check|test)|--no-verify'; then
  answer silence "No. Checks are never silenced: the patch guard refuses it. Fix the code; your brief lists how to fix common lint errors."
fi

# 3. Dependencies.
if has 'install|dev ?dependenc|devDependenc|add (a |the )?(package|dependency|library)|package\.json|package-lock|lock ?file|yarn add|pnpm add|npm i( |$)'; then
  answer dependencies "No. Dependencies are already installed in your worktree (D65). Never install, add or upgrade one, and never change package.json or a lock file. If a test needs a package that is not installed, stop without a patch and name it."
fi

# 4. The checks themselves.
if has 'commands\.env|lint (command|config)|test command|eslint\.config|\.eslintrc|lint-baseline|health-baseline|change (the )?(lint|test) (cmd|command|config|script)'; then
  answer checks "No. The checks are the commands in .factory/commands.env and the repo's lint config, with the lint baseline; none of them changes in a ticket. Make the code pass them."
fi

# 5. Changing a frozen path (tests under it stay allowed, D61).
frozen="$(frozen_paths "$dir/spec.md")"
if [ -n "$frozen" ] && has '(^|[^a-z])(modify|modifying|change|changing|edit|editing|refactor|rewrite|export|exporting|patch|touch|fix|fixing|update|updating)([^a-z]|$)'; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if grep -qF -- "${p%\*}" <<<"$question"; then
      answer frozen "Any option that changes $p is refused: $p is frozen by the contract of $feature, and the patch guard refuses any change there except test files. Options that only change tests stay open: pick the one that tests the code's public behavior (mock one level lower if needed). If none can, stop without a patch and say why."
    fi
  done <<<"$frozen"
fi
exit 1
