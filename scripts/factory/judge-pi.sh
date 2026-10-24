#!/usr/bin/env bash
# Default judge for score.sh (D97): one non-interactive pi call that only
# reads its prompt: no session, no tools, no extensions, skills, prompt
# templates or context files (the judge needs nothing from the repo, and must
# not act in it). stdin closed: pi -p waits on an open stdin.
# Usage: judge-pi.sh <model> <prompt-file>
set -euo pipefail
model="${1:?usage: judge-pi.sh <model> <prompt-file>}"; prompt="${2:?usage: judge-pi.sh <model> <prompt-file>}"
read -r -a pi_cmd <<<"${FACTORY_PI_CMD:-pi}"
[ -z "${FACTORY_PI_BIN:-}" ] || pi_cmd=("$FACTORY_PI_BIN")
"${pi_cmd[@]}" -p --no-session --no-tools --no-extensions --no-skills --no-prompt-templates --no-context-files \
  --model "$model" "$(cat "$prompt")" </dev/null
