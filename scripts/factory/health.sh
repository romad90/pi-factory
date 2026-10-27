#!/usr/bin/env bash
# Deterministic code health, the measurable half of G5 (D50). Language-
# agnostic metrics over the repo's source files, with a ratchet: a mission
# may improve them, never make them worse. The code steward (G5) judges
# what tools can't measure, with this report as evidence.
#
# Usage:
#   health.sh metrics             print the metrics (JSON)
#   health.sh details             where each finding is (dup, large, deep, skip), one per line
#   health.sh baseline            write .factory/health-baseline.json and, with FACTORY_LINT_CMD,
#                                 .factory/lint-baseline.txt (after install, or to lock in an improvement)
#   health.sh check <feature>     ratchet + FACTORY_HEALTH_CMD → .scratch/<feature>/health/report.md
#
# Metrics (source files = FACTORY_CODE_RE, minus FACTORY_EXCLUDE_RE):
#   duplicate_blocks  6-line blocks (normalized) that appear more than once, tests excluded
#   large_files       files over FACTORY_MAX_FILE_LINES (default 400), tests excluded
#   deep_lines        lines nested deeper than FACTORY_MAX_NESTING levels (default 4), tests excluded
#   debt_markers      TODO / FIXME / HACK / XXX
#   skipped_tests     .skip( .only( xit( xdescribe( @pytest.mark.skip t.Skip( @Disabled @Ignore
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

MAX_LINES="${FACTORY_MAX_FILE_LINES:-400}"
MAX_NESTING="${FACTORY_MAX_NESTING:-4}"

source_files() {                       # tracked source files; $1 = with-tests|no-tests
  local f
  while IFS= read -r f; do
    is_code_file "$f" || continue
    [ "$1" = no-tests ] && is_test_file "$f" && continue
    [ -f "$f" ] && echo "$f"
  done < <(git ls-files)
}

# Prints "<metric> <value>" lines; details to $1 (a file) for the report.
measure() {
  local details="$1" src all
  src="$(mktemp)"; all="$(mktemp)"
  source_files no-tests > "$src"; source_files with-tests > "$all"
  : > "$details"
  if [ -s "$src" ]; then
    # Duplication: windows of 6 normalized, non-trivial lines.
    tr '\n' '\0' < "$src" | xargs -0 awk -v out="$details" '
      FNR == 1 { n = 0 }
      { l = $0; gsub(/^[ \t]+|[ \t]+$/, "", l); gsub(/[ \t]+/, " ", l)
        if (l == "" || l ~ /^[]{}()[;,]+$/ || l ~ /^(end|else|fi|done|esac|\}\);?|\);?)$/ || l ~ /^(\/\/|#|\*|\/\*)/) next
        n++; buf[n] = l; at[n] = FNR
        if (n >= 6) { k = buf[n-5] "\n" buf[n-4] "\n" buf[n-3] "\n" buf[n-2] "\n" buf[n-1] "\n" buf[n]
          c[k]++; if (c[k] == 1) first[k] = FILENAME ":" at[n-5]; else if (c[k] == 2) { dups++; print "dup " FILENAME ":" at[n-5] " = " first[k] >> out } else dups++ } }
      END { print "duplicate_blocks", dups + 0 }'
    # Size and nesting.
    tr '\n' '\0' < "$src" | xargs -0 awk -v maxl="$MAX_LINES" -v maxn="$MAX_NESTING" -v out="$details" '
      function flush() { if (fname != "" && lines > maxl) { big++; print "large " fname " (" lines " lines)" >> out } }
      FNR == 1 { flush(); fname = FILENAME; lines = 0; unit = 0
        # indent unit of this file: smallest non-zero space indent (tabs count as one level)
        while ((getline l < FILENAME) > 0) { if (match(l, /^ +[^ ]/)) { w = RLENGTH - 1; if (unit == 0 || w < unit) unit = w } }
        close(FILENAME); if (unit == 0 || unit > 8) unit = 4 }
      { lines++
        if (match($0, /^\t+/)) d = RLENGTH; else if (match($0, /^ +/)) d = int(RLENGTH / unit); else d = 0
        if (d > maxn && $0 !~ /^[ \t]*$/) { deep++; if (deepf[FILENAME]++ == 0) print "deep " FILENAME ":" FNR >> out } }
      END { flush(); print "large_files", big + 0; print "deep_lines", deep + 0 }'
  else
    printf 'duplicate_blocks 0\nlarge_files 0\ndeep_lines 0\n'
  fi
  if [ -s "$all" ]; then
    # Skipped tests count in test files only: .skip( in source code is a
    # query builder's pagination (api-toolbox), not a skipped test.
    while IFS= read -r f; do is_test_file "$f" && echo "$f"; done < "$all" > "$src"
    tr '\n' '\0' < "$all" | xargs -0 awk -v out="$details" -v tests="$src" '
      BEGIN { while ((getline l < tests) > 0) tf[l] = 1; close(tests) }
      FNR == 1 { t = (FILENAME in tf) }
      /(TODO|FIXME|HACK|XXX)([^A-Za-z]|$)/ { debt++ }
      t && /\.(skip|only)\(|(^|[^A-Za-z])x(it|describe|test)\(|@pytest\.mark\.skip|t\.Skip\(|@Disabled|@Ignore/ { skip++; print "skip " FILENAME ":" FNR >> out }
      END { print "debt_markers", debt + 0; print "skipped_tests", skip + 0 }'
  else
    printf 'debt_markers 0\nskipped_tests 0\n'
  fi
  rm -f "$src" "$all"
}

to_json() { awk 'BEGIN { printf "{" } { printf "%s\"%s\": %s", (NR > 1 ? ", " : ""), $1, $2 } END { print "}" }'; }
baseline_value() {                     # <metric>
  [ -f "$FACTORY_HEALTH_BASELINE" ] || return 0
  grep -oE "\"$1\": *[0-9]+" "$FACTORY_HEALTH_BASELINE" | grep -oE '[0-9]+$' || true
}

cmd="${1:?usage: health.sh metrics | details | baseline | check <feature>}"
details="$(mktemp)"; trap 'rm -f "$details"' EXIT

case "$cmd" in
  metrics) measure "$details" | to_json ;;
  # Where each finding is: "dup <file:line> = <file:line>", "large", "deep", "skip".
  details) measure "$details" >/dev/null; cat "$details" ;;

  baseline)
    mkdir -p "$(dirname "$FACTORY_HEALTH_BASELINE")"
    measure "$details" | to_json > "$FACTORY_HEALTH_BASELINE"
    echo "Baseline written: $FACTORY_HEALTH_BASELINE $(cat "$FACTORY_HEALTH_BASELINE")"
    # D62: the lint errors the code has today; integration fails only on new ones.
    load_commands
    if [ -n "$FACTORY_LINT_CMD" ]; then
      bash -c "$FACTORY_LINT_CMD" > "$details" 2>&1 || true
      lint_keys "$details" > "$FACTORY_LINT_BASELINE"
      echo "Lint baseline written: $FACTORY_LINT_BASELINE ($(wc -l < "$FACTORY_LINT_BASELINE" | tr -d ' ') errors)"
    fi
    ;;

  check)
    feature="${2:?usage: health.sh check <feature>}"
    dir="$(mission_dir "$feature")"; [ -d "$dir" ] || die "no mission at $dir"
    mkdir -p "$dir/health"; report="$dir/health/report.md"
    load_commands
    fail=0; rows=""
    [ -f "$FACTORY_HEALTH_BASELINE" ] || die "no $FACTORY_HEALTH_BASELINE: run scripts/factory/health.sh baseline on the default branch and commit it"
    while read -r metric value; do
      base="$(baseline_value "$metric")"; base="${base:-0}"
      if [ "$value" -gt "$base" ]; then status="WORSE"; fail=1
      elif [ "$value" -lt "$base" ]; then status="better"
      else status="same"; fi
      rows+="| $metric | $base | $value | $status |"$'\n'
    done < <(measure "$details")
    if [ -n "$FACTORY_LINT_CMD" ] && [ -f "$FACTORY_LINT_BASELINE" ]; then
      lint_out="$dir/health/lint.log"; bash -c "$FACTORY_LINT_CMD" > "$lint_out" 2>&1 || true
      new_lint="$(lint_new_errors "$lint_out" | grep -c . || true)"
      if [ "$new_lint" -gt 0 ]; then status="WORSE"; fail=1; else status="same"; fi
      rows+="| lint_errors_new | 0 | $new_lint | $status |"$'\n'
    fi
    tool="not configured (FACTORY_HEALTH_CMD)"
    if [ -n "${FACTORY_HEALTH_CMD:-}" ]; then
      if bash -c "$FACTORY_HEALTH_CMD" > "$dir/health/tool.log" 2>&1; then tool="PASS ($FACTORY_HEALTH_CMD)"
      else tool="FAIL ($FACTORY_HEALTH_CMD; log: $dir/health/tool.log)"; fail=1; fi
    fi
    base_commit="$(mission_base "$feature")"
    changed="$(changed_code_files "$base_commit" HEAD)"
    {
      echo "# Health report: $feature"
      echo "**Result:** $([ "$fail" -eq 0 ] && echo PASS || echo FAIL)"
      echo "**Commit:** $(git rev-parse HEAD)"
      echo "**Mission base:** $base_commit"
      echo
      echo "## Ratchet (repo-wide; may improve, never worsen)"
      echo "| Metric | Baseline | Now | Status |"; echo "|---|---|---|---|"
      printf '%s' "$rows"
      echo; echo "**Repo tool:** $tool"
      echo; echo "## Changed source files in this mission"
      if [ -n "$changed" ]; then printf -- '- %s\n' $changed; else echo "- none"; fi
      echo; echo "## Locations (first occurrences)"
      if [ -s "$details" ]; then sort -u "$details" | awk 'NR <= 40' | sed 's/^/- /'; else echo "- none"; fi
    } > "$report"
    cat "$report"
    exit "$fail"
    ;;

  *) die "usage: health.sh metrics | details | baseline | check <feature>" ;;
esac
