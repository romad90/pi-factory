#!/usr/bin/env bash
# Local health check for the factory on this machine (run from the repo root).
# CI covers the repo itself (skills pin, models, gates); this covers the laptop.
#
# Usage: scripts/factory/doctor.sh            full check (after install, model changes)
#        scripts/factory/doctor.sh --quick    pre-flight before every /factory run (D46)
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
want_pkg="pi-subagents@0.76.1"
fail=0
ok()  { printf '  ✓ %s\n' "$*"; }
bad() { printf '  ✗ %s\n' "$*"; fail=1; }

# Pre-flight: everything that made a wave fail for avoidable reasons in
# mission 1 (network down, no tests configured, dirty tree, broken models),
# caught before any request is spent.
if [ "${1:-}" = "--quick" ]; then
  # shellcheck source=lib.sh
  . "$here/lib.sh"
  echo "Pre-flight"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] \
    && ok "at the repo root" || bad "run from the repo root"
  command -v node >/dev/null && ok "node" || bad "node not on PATH"
  load_commands
  [ -n "$FACTORY_TEST_CMD" ] && ok "tests configured" || bad "FACTORY_TEST_CMD empty in .factory/commands.env"
  dirty="$(git status --porcelain --untracked-files=no -- . ":(exclude)${FACTORY_DIR}" 2>/dev/null)"
  [ -z "$dirty" ] && ok "clean tree outside ${FACTORY_DIR}/" || bad "uncommitted changes outside ${FACTORY_DIR}/ (commit or stash)"
  if node "$here/models-lint.mjs" >/dev/null 2>&1; then ok "models: one per role, families separated"
  else bad "models-lint fails (node scripts/factory/models-lint.mjs)"; fi
  if [ -n "$FACTORY_GATEWAY_URL" ]; then
    if curl -sS -m 5 -o /dev/null "$FACTORY_GATEWAY_URL" 2>/dev/null; then ok "model gateway reachable"
    else bad "model gateway unreachable ($FACTORY_GATEWAY_URL): VPN or network down?"; fi
  else
    printf '  - gateway check skipped (set FACTORY_GATEWAY_URL in .factory/commands.env)\n'
  fi
  [ "$fail" -eq 0 ] && echo "PREFLIGHT: OK" || echo "PREFLIGHT: FAIL"
  exit "$fail"
fi

echo "Tooling"
if command -v pi >/dev/null; then ok "pi $(pi --version 2>/dev/null | awk 'NR == 1')"; else bad "pi not on PATH"; fi
if command -v node >/dev/null; then ok "node $(node --version)"; else bad "node not on PATH (needed by models-lint and the worktree hook)"; fi
if command -v pi >/dev/null; then
  pkgs="$(pi list 2>/dev/null || true)"
  if grep -qE '(^|[^/])pi-subagents' <<<"$pkgs"; then ok "pi-subagents installed"
  else bad "install $want_pkg (D29)"; fi
  grep -q "@tintinweb/pi-subagents" <<<"$pkgs" && bad "@tintinweb/pi-subagents still installed: two orchestration tools confuse the lead"
  grep -q "0.76.1" <<<"$pkgs" || printf '  ! pinned version is %s; check "pi list" (D29)\n' "$want_pkg"
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
