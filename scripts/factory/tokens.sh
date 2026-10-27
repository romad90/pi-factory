#!/usr/bin/env bash
# factory tokens <mission> [--budget N] [--top N] [--json]: where a mission's
# tokens go (P20). See tokens.mjs.
here="$(cd "$(dirname "$0")" && pwd)"
exec bash "$here/archive.sh" tokens "$@"
