#!/usr/bin/env bash
# The cockpit (P10, D90): a read-only page over status.sh's snapshot.
# Serves only a temp folder holding the page and state.json (never the repo),
# on 127.0.0.1, and rewrites state.json every few seconds.
#
# Usage: scripts/factory/cockpit.sh            serve on http://127.0.0.1:$FACTORY_COCKPIT_PORT (7357)
#        FACTORY_COCKPIT_HOSTS="<ide host or .suffix>"   behind a cloud IDE's port forwarding
#        FACTORY_COCKPIT_BIND=0.0.0.0                    only if the forwarding can't reach loopback (warns)
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
# Behind a cloud IDE's port forwarding, the browser sends the IDE's host name,
# not 127.0.0.1: list it (or a suffix starting with ".") in FACTORY_COCKPIT_HOSTS.
# The address stays loopback unless FACTORY_COCKPIT_BIND says otherwise.
bind="${FACTORY_COCKPIT_BIND:-127.0.0.1}"; extra="${FACTORY_COCKPIT_HOSTS:-}"
case "$bind" in
  127.*|localhost|::1) ;;
  *) echo "cockpit: WARNING: listening on $bind: anyone who can reach this machine on port $port can read the missions' state (specs, decisions, verdicts)." >&2
     [ -n "$extra" ] || echo "cockpit: and only the Host names in FACTORY_COCKPIT_HOSTS (plus localhost) are answered: set it, or every request is refused." >&2 ;;
esac
site="$(mktemp -d)"; cp "$here/cockpit.html" "$site/index.html"; snapshot "$site"
( while sleep "$every"; do snapshot "$site"; done ) & loop=$!
srv=""
trap 'kill $loop $srv 2>/dev/null; rm -rf "$site"' EXIT
trap 'exit 0' INT TERM
echo "cockpit: http://127.0.0.1:$port  (on $bind; read-only; Ctrl+C to stop)${extra:+; also answers Host $extra}"
SITE="$site" PORT="$port" BIND="$bind" EXTRA="$extra" node -e '
const http = require("http"), fs = require("fs"), path = require("path");
const site = process.env.SITE, types = { ".html": "text/html; charset=utf-8", ".json": "application/json" };
const port = Number(process.env.PORT), hosts = [`127.0.0.1:${port}`, `localhost:${port}`];
// Extra names a forwarding proxy sends: exact (with or without the port), or a suffix starting with ".".
const extra = String(process.env.EXTRA || "").toLowerCase().split(/\s+/).filter(Boolean);
const allowed = (h) => { const name = h.replace(/:\d+$/, "");
  return hosts.includes(h) || extra.some((e) => e === h || e === name || (e.startsWith(".") && name.endsWith(e))); };
const refused = new Set();
http.createServer((req, res) => {
  // Only names we were told about: a page elsewhere cannot rebind a domain to us (DNS rebinding).
  const h = String(req.headers.host || "").toLowerCase();
  if (!allowed(h)) {
    if (!refused.has(h)) { refused.add(h); console.error(`cockpit: refused Host ${h || "(none)"}: if your IDE forwards from that name, add it to FACTORY_COCKPIT_HOSTS`); }
    res.writeHead(403); return res.end("cockpit: this Host is not allowed (FACTORY_COCKPIT_HOSTS)"); }
  const name = req.url.split("?")[0] === "/" ? "index.html" : path.basename(req.url.split("?")[0]);
  if (!["index.html", "state.json"].includes(name)) { res.writeHead(404); return res.end(); }
  fs.readFile(path.join(site, name), (err, data) => {
    if (err) { res.writeHead(503); return res.end("no snapshot yet"); }
    res.writeHead(200, { "Content-Type": types[path.extname(name)], "Cache-Control": "no-store" }); res.end(data);
  });
}).listen(port, process.env.BIND);
' & srv=$!
wait "$srv"
