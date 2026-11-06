#!/usr/bin/env bash
# Before the plain-writing check blocks anything (D111): does it find the
# text that was actually misread? For each past mission, the check's
# findings per rule next to what readers struggled with: critique and
# verdict lines that name an ambiguity, and FAIL verdicts. Read-only.
#
# Usage: scripts/factory/prose-baseline.sh [mission-dir...]
#   default: every .scratch/<mission>/ here and every mission folder under
#   ${FACTORY_DATA_DIR:-~/.pi-factory/data}/<repo>/
# Few missions make this a sanity check, not statistics: it shows which
# rules fire where misreadings happened and which fire everywhere (noise).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"
shopt -s nullglob
dirs=("$@")
if [ ${#dirs[@]} -eq 0 ]; then
  for d in .scratch/*/ "${FACTORY_DATA_DIR:-$HOME/.pi-factory/data}/$(repo_name)"/*/; do
    [ -f "$d/spec.md" ] || [ -d "$d/verdicts" ] && dirs+=("${d%/}")
  done
fi
[ ${#dirs[@]} -gt 0 ] || die "no mission folder found: pass them (a folder with spec.md or verdicts/)"
g=(); [ ! -f GLOSSARY.md ] || g=(--glossary GLOSSARY.md)
AMBIG='ambigu|unclear|vague|undefined|could mean|two readings|interpret|not specified|unspecified|which one|underspecified|misread'
printf '| mission | prose lines | long | passive | vague | glossary | ambiguity remarks | FAIL verdicts |\n|---|---|---|---|---|---|---|---|\n'
tl=0; tp=0; tv=0; tg=0; ta=0
for d in "${dirs[@]}"; do
  files=(); for f in "$d/spec.md" "$d/strategy.md" "$d/pr.md" "$d"/verdicts/*.md "$d"/*critique*.md; do [ -f "$f" ] && files+=("$f"); done
  [ ${#files[@]} -gt 0 ] || continue
  out="$(node "$here/prose-lint.mjs" "${g[@]}" "${files[@]}" || true)"
  lines="$(cat "${files[@]}" | grep -cvE '^\s*$|^\s*(#|\||```|>)' || true)"
  l="$(grep -c ': long ' <<<"$out" || true)"; p="$(grep -c ': passive ' <<<"$out" || true)"
  v="$(grep -c ': vague ' <<<"$out" || true)"; gl="$(grep -c 'GLOSSARY.md' <<<"$out" || true)"
  crit=(); for f in "$d"/*critique*.md "$d"/verdicts/*.md; do [ -f "$f" ] && crit+=("$f"); done
  a=0; [ ${#crit[@]} -eq 0 ] || a="$(cat "${crit[@]}" | grep -ciE "$AMBIG" || true)"
  fails=0; [ ! -d "$d/verdicts" ] || fails="$(cat "$d"/verdicts/*.md 2>/dev/null | grep -cE '^\*\*Result:\*\* FAIL' || true)"
  printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' "$(basename "$d")" "$lines" "$l" "$p" "$v" "$gl" "$a" "$fails"
  tl=$((tl + l)); tp=$((tp + p)); tv=$((tv + v)); tg=$((tg + gl)); ta=$((ta + a))
done
printf '\nTotals: long %s, passive %s, vague %s, glossary %s; ambiguity remarks %s.\n' "$tl" "$tp" "$tv" "$tg" "$ta"
echo "Read it as: a rule whose count rises with the ambiguity remarks earns a place; one that fires the same everywhere is noise. The ambiguity remarks themselves: grep -iE '$AMBIG' on the critiques and verdicts."
