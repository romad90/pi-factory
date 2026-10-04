#!/usr/bin/env bash
# Pi factory installer. Non-destructive: replaced files are backed up.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PI_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
SHARED="$HOME/.agents"
BACKUP="$PI_DIR/.backup-$(date +%Y%m%d-%H%M%S)"
SKILLS=(grill-me grill-with-docs to-prd to-issues tdd diagnose improve-codebase-architecture write-a-skill setup-matt-pocock-skills)

mkdir -p "$PI_DIR/agents" "$PI_DIR/prompts" "$SHARED/skills" "$BACKUP"

backup_copy() { # src dest
  if [ -e "$2" ] && [ ! -L "$2" ]; then mkdir -p "$BACKUP/$(dirname "${2#$HOME/}")"; cp "$2" "$BACKUP/${2#$HOME/}"; fi
  cp "$1" "$2"
}

echo "→ Global rules: $SHARED/AGENTS.md (symlinked into Pi)"
backup_copy "$ROOT/global/AGENTS.md" "$SHARED/AGENTS.md"
if [ -e "$PI_DIR/AGENTS.md" ] && [ ! -L "$PI_DIR/AGENTS.md" ]; then mv "$PI_DIR/AGENTS.md" "$BACKUP/pi-AGENTS.md"; fi
ln -sfn "$SHARED/AGENTS.md" "$PI_DIR/AGENTS.md"

echo "→ Pi config, agents, prompts"
backup_copy "$ROOT/agent/models.json" "$PI_DIR/models.json"
backup_copy "$ROOT/agent/settings.json" "$PI_DIR/settings.json"
for f in "$ROOT"/agent/agents/*.md;  do backup_copy "$f" "$PI_DIR/agents/$(basename "$f")"; done
for f in "$ROOT"/agent/prompts/*.md; do backup_copy "$f" "$PI_DIR/prompts/$(basename "$f")"; done

echo "→ Matt Pocock skills into $SHARED/skills"
TMP="$(mktemp -d)"
if git clone --depth 1 https://github.com/mattpocock/skills "$TMP/mp" >/dev/null 2>&1; then
  for s in "${SKILLS[@]}"; do
    dir="$(find "$TMP/mp" -type f -name SKILL.md -path "*/$s/SKILL.md" | head -n1 | xargs -r dirname)"
    if [ -n "$dir" ]; then rm -rf "$SHARED/skills/$s"; cp -r "$dir" "$SHARED/skills/$s"; echo "  ✓ $s"
    else echo "  ✗ $s not found (renamed upstream?)"; fi
  done
else
  echo "  ✗ clone failed — copy skill folders into $SHARED/skills/ by hand"
fi
rm -rf "$TMP"

echo "→ Subagents extension (tintinweb)"
if command -v pi >/dev/null 2>&1; then
  pi install npm:@tintinweb/pi-subagents || echo "  ✗ install failed — install @tintinweb/pi-subagents by hand"
else
  echo "  ✗ pi not on PATH"
fi

echo
echo "Backup: $BACKUP"
echo "Next: edit $PI_DIR/models.json (endpoint, key, exact ids), then follow README 'Checks'."
