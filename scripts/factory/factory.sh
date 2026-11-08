#!/usr/bin/env bash
# One entry point to the factory (P11, D92), run from a project folder.
#
#   factory onboard [--ci mr|child] [--migrate]   onboard this project on the installed factory
#   factory link [--check]                        (re)create this machine's links to the package
#   factory models apply --user [profile]         this machine's models, for every project
#   factory models lint | probe                   the same as models-lint, models-probe
#   factory version                               the installed factory and what this project expects
#   factory setup [--write]                       find and rehearse this project's commands (D102)
#   factory report [--full]                       one redacted text with what a diagnosis needs (D102)
#   factory tokens <mission> [--budget N|--shape] request sizes per run and what fills them (P20)
#   factory frictions <mission> [--json]          failed, repeated and refused tool calls, by cause (P23)
#   factory measure <job>                         a job's measurements: shape, tests, churn, mutation, risks (D105)
#   factory verify <mission>                      run the done condition's commands, no model (D106)
#   factory learn [--raw]                         every project's retros, recurring findings first, scrubbed to share
#   factory learn-loop <project-dir>...           raw records → events.tsv, and every recorded guard refusal replayed (P26)
#   factory learn-export [--source x] <dir>...    the same, as a lesson file with only the factory's words, for a machine whose records stay there (P27)
#   factory <script> [args]                       any scripts/factory/<script>.sh or .mjs
#                                                 (next, status, doctor, integrate, mr, metrics …)
#
# Put it on your PATH once per machine, e.g.
#   alias factory="<package>/scripts/factory/factory.sh"
set -euo pipefail
here="$(cd -P "$(dirname "$0")" && pwd)"
cmd="${1:-help}"; [ $# -gt 0 ] && shift

case "$cmd" in
  help|-h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
  version)
    printf 'installed: %s (%s)\n' "$(cat "$here/../../.factory/VERSION")" "$(cd -P "$here/../.." && pwd)"
    if [ -f .factory/VERSION ]; then printf 'project expects: %s\n' "$(cat .factory/VERSION)"; fi
    exit 0 ;;
  models)
    case "${1:-}" in             # "factory models lint|probe" is what people type
      lint) shift; exec bash "$here/factory.sh" models-lint "$@" ;;
      probe) shift; exec bash "$here/factory.sh" models-probe "$@" ;;
    esac
    exec node "$here/models-profile.mjs" "$@" ;;
esac
case "$cmd" in */*|.*) echo "factory: unknown command: $cmd" >&2; exit 2 ;; esac
if [ -f "$here/$cmd.sh" ]; then exec bash "$here/$cmd.sh" "$@"; fi
for ext in mjs cjs; do
  if [ -f "$here/$cmd.$ext" ]; then exec node "$here/$cmd.$ext" "$@"; fi
done
echo "factory: unknown command: $cmd (factory help)" >&2; exit 2
