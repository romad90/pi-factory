#!/usr/bin/env bash
# factory frictions <mission> [--top N] [--json]: where agents fought their
# setup, read from the archived transcripts (P23). See frictions.mjs.
here="$(cd "$(dirname "$0")" && pwd)"
exec bash "$here/archive.sh" frictions "$@"
