#!/usr/bin/env bash
# factory learn [--json] [--raw]: every project's retros on this machine, scrubbed to share. See learn.mjs.
here="$(cd "$(dirname "$0")" && pwd)"
exec node "$here/learn.mjs" "$@"
