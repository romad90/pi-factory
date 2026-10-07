#!/usr/bin/env bash
# Local health check for the factory on this machine (run from the repo root).
# CI covers the repo itself (skills pin, models, gates); this covers the laptop.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
want_pkg="pi-subagents@0.76.1"
fail=0
ok()  { printf '  ✓ %s\n' "$*"; }
bad() { printf '  ✗ %s\n' "$*"; fail=1; }

echo "Tooling"
if command -v pi >/dev/null; then ok "pi $(pi --version 2>/dev/null | head -1)"; else bad "pi not on PATH"; fi
if command -v node >/dev/null; then ok "node $(node --version)"; else bad "node not on PATH (needed by models-lint and the worktree hook)"; fi
if command -v pi >/dev/null; then
  pkgs="$(pi list 2>/dev/null || true)"
  if printf '%s' "$pkgs" | grep -qE '(^|[^/])pi-subagents'; then ok "pi-subagents installed"
  else bad "install $want_pkg (D29)"; fi
  printf '%s' "$pkgs" | grep -q "@tintinweb/pi-subagents" && bad "@tintinweb/pi-subagents still installed: two orchestration tools confuse the lead"
  printf '%s' "$pkgs" | grep -q "0.76.1" || printf '  ! pinned version is %s; check "pi list" (D29)\n' "$want_pkg"
fi

echo "pi-subagents config (user level)"
cfg="$HOME/.pi/agent/extensions/subagent/config.json"
if [ -f "$cfg" ] && grep -q 'factory-worktree-hook.mjs' "$cfg"; then ok "worktree hook shim configured"
else bad "run scripts/factory/install-pi-config.sh (worktree hook hides the instrument, D35)"; fi

echo
bash "$here/skills-pin.sh" verify || fail=1
echo
bash "$here/skills-pin.sh" check-global
echo
node "$here/models-lint.mjs" || fail=1

cat <<MSG

Inside pi, finish with:
  /subagents-doctor            package health
  /subagents-models            each factory agent on its configured model?
  "list the available subagents"  only factory-* agents, no skills listed as agents
MSG
exit "$fail"
