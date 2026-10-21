#!/usr/bin/env bash
# The cockpit (P10, D90): a read-only page over status.sh's snapshot.
# Serves only a temp folder holding the page and state.json (never the repo),
# on 127.0.0.1, and rewrites state.json every few seconds.
#
# Usage: scripts/factory/cockpit.sh            serve on http://127.0.0.1:$FACTORY_COCKPIT_PORT (7357)
#        scripts/factory/cockpit.sh --once DIR write cockpit.html and state.json to DIR, then exit
# Interval: $FACTORY_COCKPIT_EVERY seconds (default 3). Stop with Ctrl+C.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

snapshot() {                             # <dir>
  local tmp="$1/state.json.tmp"
  if bash "$here/status.sh" --all --json > "$tmp" 2>"$1/status.err"; then mv "$tmp" "$1/state.json"; else rm -f "$tmp"; fi
}

if [ "${1:-}" = "--once" ]; then
  out="${2:?usage: cockpit.sh --once <dir>}"; mkdir -p "$out"
  cp "$here/cockpit.html" "$out/index.html"; snapshot "$out"
  [ -f "$out/state.json" ] || die "snapshot failed: $(cat "$out/status.err")"
  echo "cockpit: $out/index.html (state.json written)"; exit 0
fi

port="${FACTORY_COCKPIT_PORT:-7357}"; every="${FACTORY_COCKPIT_EVERY:-3}"
site="$(mktemp -d)"; cp "$here/cockpit.html" "$site/index.html"; snapshot "$site"
( while sleep "$every"; do snapshot "$site"; done ) & loop=$!
srv=""
trap 'kill $loop $srv 2>/dev/null; rm -rf "$site"' EXIT
trap 'exit 0' INT TERM
echo "cockpit: http://127.0.0.1:$port  (read-only; Ctrl+C to stop)"
SITE="$site" PORT="$port" node -e '
const http = require("http"), fs = require("fs"), path = require("path");
const site = process.env.SITE, types = { ".html": "text/html; charset=utf-8", ".json": "application/json" };
const port = Number(process.env.PORT), hosts = [`127.0.0.1:${port}`, `localhost:${port}`];
http.createServer((req, res) => {
  // Only this machine, by name too: a page elsewhere cannot rebind a domain to us.
  if (!hosts.includes(String(req.headers.host || "").toLowerCase())) { res.writeHead(403); return res.end(); }
  const name = req.url.split("?")[0] === "/" ? "index.html" : path.basename(req.url.split("?")[0]);
  if (!["index.html", "state.json"].includes(name)) { res.writeHead(404); return res.end(); }
  fs.readFile(path.join(site, name), (err, data) => {
    if (err) { res.writeHead(503); return res.end("no snapshot yet"); }
    res.writeHead(200, { "Content-Type": types[path.extname(name)], "Cache-Control": "no-store" }); res.end(data);
  });
}).listen(port, "127.0.0.1");
' & srv=$!
wait "$srv"
