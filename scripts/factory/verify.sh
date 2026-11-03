#!/usr/bin/env bash
# The mission's done condition, run by a script (P23): every command in
# backticks under "## Done when" in spec.md must exit 0. No model judges it.
# Written to .scratch/<mission>/verify.md with the commit it ran on; next.sh
# runs it after code health, before the MR, and again when code changes.
#
# Usage: scripts/factory/verify.sh <mission>
#
# A done condition is a command that exits 0 only when the mission is done:
# `npm test`, `npx api-extractor run` (fails on a changed API report),
# `npx stryker run --thresholds.break 70` (fails under 70%). Each command is
# checked by the command guard's rules first, as an agent's would be: the
# strategy or spec that holds it was approved by a person, and still nothing
# that would be refused to an agent runs here.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: verify.sh <mission>}"
dir="$(mission_dir "$feature")"; spec="$dir/spec.md"
[ -f "$spec" ] || die "no mission '$feature'"
mapfile -t cmds < <(done_commands "$spec")
[ ${#cmds[@]} -gt 0 ] || die "no command in backticks under \"## Done when\" in $spec"
out="$dir/verify.md"; tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
result=PASS; rows=""
for c in "${cmds[@]}"; do
  if why="$(FACTORY_ROLE=worker node -e '
      import(process.argv[1]).then(({ check }) => {
        const hit = check({ tool: "bash", input: { command: process.argv[2] }, cwd: process.cwd() });
        if (hit) { console.log(hit.rule + ": " + hit.reason); process.exit(1); } });' "$here/guard-rules.mjs" "$c")"; then :
  else
    result=FAIL; rows+="- \`$c\`: REFUSED by the command guard ($why)"$'\n'; continue
  fi
  start="$(date +%s)"; rc=0
  bash -c "$c" > "$tmp" 2>&1 </dev/null || rc=$?
  secs=$(( $(date +%s) - start ))
  [ "$rc" -eq 0 ] || result=FAIL
  # The end of its output, redacted (a test log can print a secret).
  tail_out="$(node -e 'import(process.argv[1]).then(({ redact }) => { const l = redact(require("fs").readFileSync(process.argv[2], "utf8")).split("\n").filter((x) => x.trim()); console.log(l.slice(-12).map((x) => "  " + x.slice(0, 200)).join("\n")); })' "$here/redact.mjs" "$tmp")"
  rows+="- \`$c\`: exit $rc in ${secs}s"$'\n'"  \`\`\`"$'\n'"$tail_out"$'\n'"  \`\`\`"$'\n'
done
{ printf '# Verify: %s\n**Result:** %s\n**Commit:** %s\n**Run:** %s\n\n' "$feature" "$result" "$(git rev-parse HEAD)" "$(date '+%F %H:%M')"
  printf 'The done condition under "## Done when" in spec.md, run by scripts/factory/verify.sh.\n\n%s' "$rows"; } > "$out"
bash "$here/checkpoint.sh" "$feature" >/dev/null
echo "verify: $result ($out)"
[ "$result" = PASS ]
