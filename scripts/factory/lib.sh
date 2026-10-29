#!/usr/bin/env bash
# Shared helpers for the factory scripts. Sourced by next.sh, coverage.sh,
# gate.sh, workflow.sh, brief.sh, integrate.sh and the others. Formats are defined in docs/agents/*.md.
# Rationale for each rule: docs/adr/ADR-001-agentic-factory.md.

FACTORY_DIR="${FACTORY_DIR:-.scratch}"            # one path segment, no slash
# Some workspace images ship without coreutils' head (D102); every
# "… | head -1" would then stop a script under pipefail. This stand-in covers
# what the factory calls (-N, -n N, -nN, -c N, files, stdin), reads all its
# input (an early exit would send SIGPIPE upstream) and is defined only when
# head is missing.
if ! command -v head >/dev/null 2>&1; then
  head() {
    local n=10 c=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -n) n="$2"; shift 2 ;;
        -n*) n="${1#-n}"; shift ;;
        -c) c="$2"; shift 2 ;;
        -c*) c="${1#-c}"; shift ;;
        -[0-9]*) n="${1#-}"; shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    if [ -n "$c" ]; then
      node -e 'const fs = require("fs"); const n = Number(process.argv[1]); const f = process.argv.slice(2);
        const b = f.length ? Buffer.concat(f.map((x) => fs.readFileSync(x))) : fs.readFileSync(0);
        process.stdout.write(b.subarray(0, n));' "$c" "$@"
    else
      sed -n "1,${n}p" "$@"
    fi
  }
fi
FACTORY_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FACTORY_ROUND_LIMIT="${FACTORY_ROUND_LIMIT:-3}"
FACTORY_BEHAVIOR_PATHS_FILE="${FACTORY_BEHAVIOR_PATHS_FILE:-.factory/behavior-paths}"
FACTORY_DOCS_RE="${FACTORY_DOCS_RE:-^(docs/|[^/]*\.md$)}"
FACTORY_INSTRUMENT_DIR="${FACTORY_INSTRUMENT_DIR:-instrument}"  # hidden from workers (D21)
# Tickets per wave (D27): environment first, then .factory/commands.env, else 4.
# A gateway with a low request limit wants 1 or 2 (D58).
if [ -z "${FACTORY_MAX_PARALLEL:-}" ] && [ -f .factory/commands.env ]; then
  FACTORY_MAX_PARALLEL="$(sed -n 's/^[[:space:]]*\(export[[:space:]]*\)\{0,1\}FACTORY_MAX_PARALLEL=["'"'"']\{0,1\}\([0-9][0-9]*\).*/\2/p' .factory/commands.env | tail -1)"
fi
FACTORY_MAX_PARALLEL="${FACTORY_MAX_PARALLEL:-4}"
# The factory's own files: in this project when it was copied in, else in the
# package installed once per machine (P11, D92); scripts/factory is then a
# local link to it.
FACTORY_LIB_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FACTORY_PACKAGE_ROOT="$(cd -P "$FACTORY_LIB_DIR/../.." && pwd)"
# version_cmp a b → -1, 0 or 1 (x.y.z, a prerelease x.y.z-rc.N before x.y.z).
version_cmp() {
  node -e '
const p = (v) => { const [core, pre] = String(v).replace(/^v/, "").split("-"); return [...core.split(".").map(Number), pre ? Number((pre.match(/\d+/) || [0])[0]) : Infinity]; };
const a = p(process.argv[1]), b = p(process.argv[2]);
for (let i = 0; i < 4; i++) if (a[i] !== b[i]) { console.log(a[i] < b[i] ? -1 : 1); process.exit(0); }
console.log(0);' "$1" "$2"
}
factory_res() { if [ -e "$1" ]; then printf '%s' "$1"; else printf '%s' "$FACTORY_PACKAGE_ROOT/$1"; fi; }
FACTORY_SKILLS_DIR="${FACTORY_SKILLS_DIR:-$(factory_res .pi/skills)}"   # pinned skills (D36)
FACTORY_BRIEFS_DIR="${FACTORY_BRIEFS_DIR:-.factory/briefs}"     # brief templates (D32)
# Agent files: $FACTORY_AGENTS_DIR, else .pi/agents/factory, else the installed
# package's; models are resolved with the settings overrides (D31, D92).
FACTORY_FIX_MAX_LINES="${FACTORY_FIX_MAX_LINES:-80}"            # fix-lane blast radius (D41)
FACTORY_HEALTH_BASELINE="${FACTORY_HEALTH_BASELINE:-.factory/health-baseline.json}"  # ratchet (D50)
# Source files the health checks and the steward look at (D49, D50).
FACTORY_CODE_RE="${FACTORY_CODE_RE:-\.(js|jsx|ts|tsx|mjs|cjs|py|go|java|kt|kts|rb|rs|cs|php|scala|swift|sh)$}"
FACTORY_TEST_RE="${FACTORY_TEST_RE:-(^|/)(tests?|__tests__|spec|specs)/|[._-](test|spec)\.[a-z]+$|_test\.(go|py)$}"
FACTORY_EXCLUDE_RE="${FACTORY_EXCLUDE_RE:-^(\.scratch|\.pi|\.factory|scripts/factory|instrument|node_modules|vendor|dist|build|coverage)/}"

die() { printf 'factory: %s\n' "$*" >&2; exit 2; }

mission_dir()  { printf '%s/%s' "$FACTORY_DIR" "$1"; }

# --- context repos and investigation (D99) ------------------------------------
# A mission changes one repo. Other repos it must understand are listed in the
# spec, cloned read-only into FACTORY_CONTEXT_DIR by context.sh, and mapped by
# explorers before an investigator concludes where the fix belongs.
FACTORY_CONTEXT_DIR="${FACTORY_CONTEXT_DIR:-.factory/context}"
FACTORY_INVESTIGATE_ROUNDS="${FACTORY_INVESTIGATE_ROUNDS:-3}"

# context_repos <spec> → name \t source \t branch \t role, one line per repo,
# from "## Context repos": "- <url or path>[@branch] — <role>".
context_repos() {
  [ -f "$1" ] && grep -q '^## Context repos' "$1" || return 0
  awk '/^## Context repos/ { f = 1; next }
       f && /^## /         { exit }
       f && /^[-*][ \t]+/  {
         line = $0; sub(/^[-*][ \t]+/, "", line); gsub(/`/, "", line); role = ""
         if (match(line, /[ \t]+(—|--|-)[ \t]+/)) { role = substr(line, RSTART + RLENGTH); line = substr(line, 1, RSTART - 1) }
         src = line; sub(/[ \t]+$/, "", src); br = ""
         if (match(src, /@[^@\/:]+$/)) { br = substr(src, RSTART + 1); src = substr(src, 1, RSTART - 1) }
         if (src == "" || tolower(src) == "none") next
         n = src; sub(/\/+$/, "", n); sub(/.*[\/:]/, "", n); sub(/\.git$/, "", n)
         print n "\t" src "\t" br "\t" role }' "$1"
}

# The investigation applies to a bugfix or an exploration that names context repos.
investigation_applies() {              # <spec>
  local intent
  [ -n "$(context_repos "$1")" ] || return 1
  intent="$(verdict_field "$1" Intent)"
  [ "$intent" = bugfix ] || [ "$intent" = exploration ]
}

# open_questions <mission dir> → id \t repo \t question, for each "- Q<n> [repo]: …"
# under "## Questions" in investigation.md without an answer file
# context/answers/Q<n>.md (one file per answer: explorers run in parallel).
open_questions() {
  local inv="$1/investigation.md"
  [ -f "$inv" ] || return 0
  awk -v ans="$1/context/answers" '
    function answered(id,   l) { if ((getline l < (ans "/" id ".md")) > 0) { close(ans "/" id ".md"); return 1 } return 0 }
    /^## Questions/ { f = 1; next }
    f && /^## /     { exit }
    f && /^[-*][ \t]+Q[0-9]+[ \t]*\[[^]]+\][ \t]*:/ {
      line = $0; sub(/^[-*][ \t]+/, "", line)
      id = line; sub(/[ \t\[].*/, "", id)
      repo = line; sub(/^[^[]*\[/, "", repo); sub(/\].*/, "", repo)
      q = line; sub(/^[^:]*:[ \t]*/, "", q)
      if (!answered(id)) print id "\t" repo "\t" q }' "$inv"
}

# fix_belongs <investigation.md>: "here" or a context repo's name, whole
# (repo names may hold spaces, unlike verdict_field's first word).
fix_belongs() {
  [ -f "$1" ] || return 0
  { grep -m1 -E '^\*\*Fix belongs:\*\*' "$1" || true; } | sed -E 's/^\*\*Fix belongs:\*\* *//; s/`//g; s/[[:space:]]+$//'
}

# investigation_rounds <mission dir>: investigate waves run so far.
investigation_rounds() { cat "$1/state/investigate.rounds" 2>/dev/null || echo 0; }

# --- contract (spec.md) ------------------------------------------------------

has_contract() { grep -q '^## Validation contract' "$1"; }

# Approvals (D101): a dated approval line counts only with the matching row
# human.sh logged in the mission's decisions.tsv (same kind, same date; for the
# contract, the latest approve-or-amend row is that approval). A line an agent
# or a hand typed, with no row, approves nothing: next.sh says so.
approval_date() {                      # <file> <Contract|Design|Conclusion> → the line's date
  [ -f "$1" ] || return 0
  { grep -m1 -E "^\*\*$2 approved:\*\* [0-9]{4}-[0-9]{2}-[0-9]{2}" "$1" || true; } | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1
}
approval_recorded() {                  # <decisions.tsv> <kind> <date>
  [ -f "$1" ] && [ -n "$3" ] || return 1
  awk -F'\t' -v k="$2" -v d="$3" '
    NR == 1 { next }
    k == "approve" && $3 == "approve" { last = $1; next }
    k == "approve" && $3 == "amend"   { last = ""; next }
    $3 == k && $1 == d                { found = 1 }
    END { exit !(k == "approve" ? last == d : found) }' "$1"
}
approved_by_human() {                  # <file> <label> <kind>
  local d; d="$(approval_date "$1" "$2")"
  [ -n "$d" ] && approval_recorded "$(dirname "$1")/decisions.tsv" "$3" "$d"
}
# A dated line without its decisions.tsv row: written by hand or by an agent.
approval_unrecorded() {                # <file> <label> <kind>
  [ -n "$(approval_date "$1" "$2")" ] && ! approved_by_human "$1" "$2" "$3"
}
contract_approved() { approved_by_human "$1" Contract approve; }
conclusion_approved() { approved_by_human "$1" Conclusion approve-conclusion; }

# Active assertion IDs. Withdrawn ones are written "### ~~VAL-…~~" and skipped.
contract_ids() {
  awk '
    /^## Validation contract/ { in_c = 1; next }
    in_c && /^## /            { in_c = 0 }
    in_c && /^### VAL-[A-Z0-9]+-[0-9][0-9][0-9]:/ {
      id = $2; sub(/:$/, "", id); print id
    }' "$1"
}

# Frozen paths (D61): what a mission must not change, from the spec's
# "## Frozen paths" section, one "- <path>" per line ("dir/" = everything
# under it, else a glob; "- none" = nothing). Without the section, a
# maintenance mission freezes FACTORY_FROZEN_MAINTENANCE (default src/):
# current behavior is the reference, so only tests and docs may move.
FACTORY_FROZEN_MAINTENANCE="${FACTORY_FROZEN_MAINTENANCE:-src/}"
frozen_paths() {                       # <spec> → one pattern per line
  [ -f "$1" ] || return 0
  if grep -q '^## Frozen paths' "$1"; then
    awk '/^## Frozen paths/ { in_f = 1; next }
         in_f && /^## /     { exit }
         in_f && /^[-*][ \t]+/ { sub(/^[-*][ \t]+/, ""); gsub(/`/, ""); sub(/[ \t]+(—|-).*$/, "")
                              if ($1 != "" && tolower($1) != "none") print $1 }' "$1"
  elif [ "$(verdict_field "$1" Intent)" = maintenance ]; then
    printf '%s\n' $FACTORY_FROZEN_MAINTENANCE
  fi
}
# Program design (D94): feature and refactor missions get one, others when the
# spec says **Design:** yes; **Design:** no skips it.
design_needed() {                      # <spec>
  local d i
  d="$(verdict_field "$1" Design | tr '[:upper:]' '[:lower:]')"
  case "$d" in yes) return 0 ;; no) return 1 ;; esac
  i="$(verdict_field "$1" Intent)"
  [ "$i" = feature ] || [ "$i" = refactor ]
}
design_approved() {                    # <design.md>
  approved_by_human "$1" Design approve-design
}
# Who approves (D95): FACTORY_APPROVER, else git's user.name.
approver() { printf '%s' "${FACTORY_APPROVER:-$(git config user.name 2>/dev/null || true)}"; }

# Frozen tests (D93): in a refactor, the tests that pin today's behavior are
# the reference, so not a line of them may change. Unlike frozen paths, the
# test-file exception does not apply. From "## Frozen tests", same syntax.
frozen_tests() {                       # <spec> → one pattern per line
  [ -f "$1" ] || return 0
  if grep -q '^## Frozen tests' "$1"; then
    awk '/^## Frozen tests/ { in_f = 1; next }
         in_f && /^## /     { exit }
         in_f && /^[-*][ \t]+/ { sub(/^[-*][ \t]+/, ""); gsub(/`/, ""); sub(/[ \t]+(—|-).*$/, "")
                              if ($1 != "" && tolower($1) != "none") print $1 }' "$1"
  fi
  # D99: a reproduction test is frozen once its ticket is integrated (green):
  # later tickets fix the code, never the test that shows the bug.
  local d t
  d="$(dirname "$1")"
  for t in "$d"/issues/*-reproduce-*.md; do
    [ -f "$t" ] && [ -f "$d/state/$(basename "$t" .md).integrated" ] || continue
    verdict_field "$t" Test | sed 's/`//g'
  done
}
is_frozen() {                          # <path> <patterns (newline-separated)>
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    p="${p#./}"
    if [[ "$p" == */ ]]; then [[ "$1" == "$p"* ]] && return 0; continue; fi
    # shellcheck disable=SC2053 # the pattern is a glob on purpose
    [[ "$1" == $p ]] && return 0
  done <<<"$2"
  return 1
}

# --- tickets (issues/NN-slug.md) --------------------------------------------

ticket_name() { basename "$1" .md; }
ticket_num()  { ticket_name "$1" | { grep -oE '^[0-9]+' || true; }; }

# Prints "enabler", or the VAL IDs listed under "## Covers".
ticket_covers() {
  awk '
    /^## Covers: *enabler/ { print "enabler"; exit }
    /^## Covers/           { in_c = 1; next }
    in_c && /^## /         { exit }
    in_c {
      while (match($0, /VAL-[A-Z0-9]+-[0-9][0-9][0-9]/)) {
        print substr($0, RSTART, RLENGTH)
        $0 = substr($0, RSTART + RLENGTH)
      }
    }' "$1" | awk '!seen[$0]++'
}

# P20: the text of the named assertions (each "### <ID>: …" block up to the
# next heading), so a brief carries what its agent needs instead of the spec.
assertion_blocks() {                     # <spec> <id>...
  local spec="$1"; shift
  [ $# -gt 0 ] || return 0
  awk -v ids=" $* " '
    /^#{1,3} / { on = 0 }
    /^### VAL-[A-Z0-9]+-[0-9][0-9][0-9]/ { id = $2; sub(/:$/, "", id); on = index(ids, " " id " ") > 0 }
    on' "$spec"
}

# First non-empty line after "## Covers: enabler".
ticket_enabler_reason() {
  awk '
    /^## Covers: *enabler/ { in_e = 1; next }
    in_e && /^## /         { exit }
    in_e && NF             { print; exit }' "$1"
}

# Ticket numbers listed under "## Blocked by". Accepts "01", "#1"-style
# two-digit refs or "01-slug". Adjust if your to-tickets output differs.
ticket_blockers() {
  awk '
    /^## Blocked by/ { in_b = 1; next }
    in_b && /^## /   { exit }
    in_b {
      while (match($0, /[0-9][0-9]/)) {
        print substr($0, RSTART, RLENGTH)
        $0 = substr($0, RSTART + RLENGTH)
      }
    }' "$1" | sort -u
}

# --- verdicts ----------------------------------------------------------------

# verdict_field <file> <Field>  → value of "**Field:** value" (first word)
verdict_field() {
  [ -f "$1" ] || return 0
  { grep -m1 -E "^\*\*$2:\*\*" "$1" || true; } \
    | sed -E 's/^\*\*[^*]+:\*\* *//' | awk '{print $1}'
}

# Round of a verdict (D38): the number of archived copies <stem>.r<N>.md,
# written by record_verdict. Never the number an agent typed. Falls back to
# the header only for verdicts recorded before history existed.
verdict_round() {
  local n
  n="$(verdict_history_count "$1")"
  if [ "$n" -gt 0 ]; then echo "$n"; return 0; fi
  [ -f "$1" ] || return 0
  { grep -m1 -oE 'round [0-9]+' "$1" || true; } | awk '{print $2}'
}

verdict_history_count() {              # <verdict file> → count of <stem>.r<N>.md
  local f="$1" n=0 h
  for h in "${f%.md}".r*.md; do [ -f "$h" ] && n=$((n + 1)); done
  echo "$n"
}

# The model a factory agent is configured with: its frontmatter, then the user's
# and the project's agentOverrides, as pi-subagents resolves it (D92). Verdicts
# carry this, never the model's own guess about itself (D39).
agent_model() {                        # <agent name>
  local m
  m="$(node "$FACTORY_LIB_DIR/effective-models.mjs" 2>/dev/null | awk -F'\t' -v n="$1" '$1 == n { print $2; exit }')"
  echo "${m:-unknown}"
}

# record_verdict <file> <agent>: makes <file> the next round of its history.
#   - round = archived copies + 1, written into the header
#   - **Model:** = the agent's configured model
#   - archived as <stem>.r<N>.md
# Idempotent: a file identical to its latest archive is not recorded again.
record_verdict() {                     # <file> <agent> [model line override]
  local f="$1" agent="$2" n latest model tmp
  [ -f "$f" ] || return 0
  n="$(verdict_history_count "$f")"
  latest="${f%.md}.r$n.md"
  if [ "$n" -gt 0 ] && cmp -s "$f" "$latest"; then return 0; fi
  n=$((n + 1)); tmp="$(mktemp)"
  model="${3:-$(agent_model "$agent") (configured for $agent)}"
  awk -v n="$n" -v model="$model" '
    NR == 1 && /^# Verdict/ {
      sub(/[ ]*(—|-)[ ]*round.*$/, ""); print $0 " — round " n; next }
    /^\*\*Model:\*\*/ { print "**Model:** " model; seen = 1; next }
    /^\*\*Commit:\*\*/ && !seen { print; print "**Model:** " model; seen = 1; next }
    { print }' "$f" > "$tmp"
  mv "$tmp" "$f"
  cp "$f" "${f%.md}.r$n.md"
}

# write_fail_verdict <feature> <ticket> <brief-label> <issue text>
# A deterministic failure (integration, worker without patch) counts as a
# round like any review FAIL, so escalation happens on its own (D38).
write_fail_verdict() {
  local feature="$1" ticket="$2" label="$3" text="$4" dir v marker
  dir="$(mission_dir "$feature")"; v="$dir/verdicts/$ticket-code.md"; mkdir -p "$dir/verdicts"
  marker="$(ticket_marker "$feature" "$ticket")"
  journal_collect "$feature" "$ticket" "FAIL ($label)"
  cat > "$v" <<VERDICT
# Verdict: $ticket — round ?
**Result:** FAIL
**Commit:** ${marker:-$(git rev-parse HEAD)}
**Model:** none
**Brief:** $label

## Issues
- [blocking] $text
VERDICT
  record_verdict "$v" factory-scripts "none (deterministic check: $label)"
}

# Evidence or label (D40). Counts the assertion lines of a verdict:
#   "- VAL-X-001: PASS — <evidence>"   pass (evidence required)
#   "- VAL-X-001: FAIL — <what>"       fail
#   "- VAL-X-001: UNVERIFIED — <why>"  unverified
# A PASS without evidence counts as unverified. Prints: pass fail unverified
verdict_evidence_counts() {
  [ -f "$1" ] || { echo "0 0 0"; return 0; }
  awk '
    /^## (Assertions|Bar)/ { in_a = 1; next }
    in_a && /^## /   { in_a = 0 }
    in_a && /^- *(VAL-[A-Z0-9]+-[0-9][0-9][0-9]|QB-[A-Z]+-[0-9][0-9])/ {
      line = $0; sub(/^- *(VAL-[A-Z0-9]+-[0-9][0-9][0-9]|QB-[A-Z]+-[0-9][0-9])[^:]*: */, "", line)
      split(line, w, /[ \t]/); status = toupper(w[1])
      ev = line; sub(/^[A-Za-z]+[ \t]*/, "", ev); sub(/^(—|–|-|:)+[ \t]*/, "", ev)
      if (status == "PASS" && ev != "") p++
      else if (status == "FAIL" || status == "FLAKY") f++
      else u++
    }
    END { printf "%d %d %d\n", p, f, u }' "$1"
}

# IDs of the assertions a verdict leaves unverified (UNVERIFIED, unlabeled,
# or PASS without evidence).
verdict_unverified_ids() {
  [ -f "$1" ] || return 0
  awk '
    /^## (Assertions|Bar)/ { in_a = 1; next }
    in_a && /^## /   { in_a = 0 }
    in_a && match($0, /(VAL-[A-Z0-9]+-[0-9][0-9][0-9]|QB-[A-Z]+-[0-9][0-9])/) {
      id = substr($0, RSTART, RLENGTH)
      line = $0; sub(/^- *(VAL-[A-Z0-9]+-[0-9][0-9][0-9]|QB-[A-Z]+-[0-9][0-9])[^:]*: */, "", line)
      split(line, w, /[ \t]/); status = toupper(w[1])
      ev = line; sub(/^[A-Za-z]+[ \t]*/, "", ev); sub(/^(—|–|-|:)+[ \t]*/, "", ev)
      if (status == "PASS" && ev != "") next
      if (status == "FAIL" || status == "FLAKY") next
      print id
    }' "$1"
}

# Human acceptance of unverified assertions, written by
# `human.sh accept-unverified`:  **Accepted unverified:** <date> VAL-…, VAL-… — <why>
accepted_unverified() {                # <spec> → accepted IDs ("ALL" for all)
  { grep -E '^\*\*Accepted unverified:\*\*' "$1" || true; } \
    | sed -E 's/ (—|-) .*$//' | grep -oE 'VAL-[A-Z0-9]+-[0-9]{3}|QB-[A-Z]+-[0-9]{2}|\bALL\b' || true
}

# A verdict is fresh when no file outside the missions dir changed
# between the commit it was produced on and HEAD.
verdict_is_fresh() {
  local sha="$1"
  [ -n "$sha" ] || return 1
  git cat-file -e "${sha}^{commit}" 2>/dev/null || return 1
  [ -z "$(git diff --relative --name-only "$sha" HEAD -- . ":(exclude)${FACTORY_DIR}")" ]
}

# Behavior verdicts go stale only when behavior changed (D42): a path in
# .factory/behavior-paths or the instrument. Without patterns, any code
# change counts (the strict rule above).
behavior_patterns() {
  [ -f "$FACTORY_BEHAVIOR_PATHS_FILE" ] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$FACTORY_BEHAVIOR_PATHS_FILE" || true
}

behavior_verdict_is_fresh() {
  local sha="$1" patterns changed
  [ -n "$sha" ] || return 1
  git cat-file -e "${sha}^{commit}" 2>/dev/null || return 1
  patterns="$(behavior_patterns)"
  [ -n "$patterns" ] || { verdict_is_fresh "$sha"; return; }
  changed="$(git diff --relative --name-only "$sha" HEAD -- . ":(exclude)${FACTORY_DIR}")"
  [ -z "$changed" ] && return 0
  ! grep -qE -f <(printf '%s\n' "$patterns"; printf '^%s/\n' "$FACTORY_INSTRUMENT_DIR") <<<"$changed"
}

# Code health verdicts (G5) go stale only when source files (code or tests)
# change: a README or values tweak doesn't need a new steward run.
code_verdict_is_fresh() {
  local sha="$1" f
  [ -n "$sha" ] || return 1
  git cat-file -e "${sha}^{commit}" 2>/dev/null || return 1
  while IFS= read -r f; do
    [ -n "$f" ] && is_code_file "$f" && return 1
  done < <(git diff --relative --name-only "$sha" HEAD -- . ":(exclude)${FACTORY_DIR}")
  return 0
}

# --- monorepo projects (D56) ---------------------------------------------------
# A project can be a folder inside a bigger repo. Factory paths stay relative
# to the project; git commands that work from the root get the prefix.

project_prefix() { local p; p="$(git rev-parse --show-prefix 2>/dev/null)"; printf '%s' "${p%/}"; }

# Rewrites a patch to paths relative to the project. Worker patches may come
# root-relative from a monorepo worktree. Exit 3 when the patch touches files
# outside the project (git apply would silently drop them).
project_patch() {                      # <in> <out>
  local prefix; prefix="$(project_prefix)"
  if [ -z "$prefix" ]; then cp "$1" "$2"; return 0; fi
  node "$FACTORY_SCRIPTS/patch-paths.mjs" project "$1" "$2" "$prefix" "$(git rev-parse --show-toplevel)" "$PWD"
}

# git apply for a project-relative patch, from the repo root in a monorepo.
project_apply() {                      # <git apply args...> <patch>
  local prefix; prefix="$(project_prefix)"
  if [ -n "$prefix" ]; then git -C "$(git rev-parse --show-toplevel)" apply --directory="$prefix" "$@"
  else git apply "$@"; fi
}

# --- draft patches (D73) -------------------------------------------------------
# A worker's latest self-checked change, kept in the git folder all worktrees
# share: never committed, and it outlives the worker's worktree.
draft_patch() {                        # <feature> <ticket>
  local common; common="$(git rev-parse --git-common-dir)"
  case "$common" in /*) ;; *) common="$(cd "$PWD/$common" && pwd)" ;; esac   # no "../.." in a monorepo
  printf '%s/pi-factory/drafts/%s/%s.patch\n' "$common" "$1" "$2"
}

# The ticket a worker's worktree is for, from its pi-subagents/<ticket>-…
# branch; the longest ticket name wins. Exits 1 outside a worker worktree.
worker_ticket() {                      # <feature>
  local branch t name best=""
  branch="$(git branch --show-current 2>/dev/null)"
  [[ "$branch" == pi-subagents/* ]] || return 1
  for t in "$(mission_dir "$1")"/issues/*.md; do
    [ -f "$t" ] || continue
    name="$(basename "$t" .md)"
    [[ "$branch" == "pi-subagents/$name-"* ]] && [ ${#name} -gt ${#best} ] && best="$name"
  done
  [ -n "$best" ] || return 1
  printf '%s\n' "$best"
}

# D84: move a worker's journal (journal.sh) into the mission, under a round
# header, so the next round reads what this one tried. No journal: nothing.
journal_collect() {                    # <feature> <ticket> <outcome>
  local src out n
  src="$(draft_patch "$1" "$2").journal"
  [ -s "$src" ] || return 0
  out="$(mission_dir "$1")/journal/$2.md"; mkdir -p "$(dirname "$out")"
  n="$(verdict_history_count "$(mission_dir "$1")/verdicts/$2-code.md")"
  { [ -s "$out" ] || printf '# Journal: %s\n' "$2"
    printf '\n## Round %s · %s · %s\n' "$((n + 1))" "$(date '+%F %H:%M')" "$3"
    cat "$src"; } >> "$out"
  rm -f "$src"
}

# D84: the failures of a red integration, reduced to what stays the same
# between two runs of the same mistake (test names, lint keys; no times or
# counts). Empty when nothing recognizable failed.
failure_signature() {                  # <log>
  grep -E '^[[:space:]]*(FAIL|✗|×|not ok|Error:|[A-Za-z]+Error:)|new errors' "$1" 2>/dev/null \
    | sed -E 's/[0-9]+(\.[0-9]+)?[[:space:]]*(ms|s)\b//g; s/:[0-9]+(:[0-9]+)?//g; s/[[:space:]]+/ /g; s/^ //; s/ $//' \
    | sort -u | head -40
}

# --- the factory's own identity (D100) ---------------------------------------
# Commits the factory makes are authored by it, committed by the human whose
# git identity runs the mission: `git log --author=pi-factory` is what the
# factory did, `--committer` who let it.
FACTORY_AUTHOR="${FACTORY_AUTHOR:-pi-factory <pi-factory@localhost>}"

# --- commands.env (D8, D34) ---------------------------------------------------

load_commands() {
  FACTORY_LINT_CMD=""; FACTORY_TEST_CMD=""; FACTORY_EXTRA_CMD=""; FACTORY_GATEWAY_URL=""; FACTORY_HEALTH_CMD=""; FACTORY_GATEWAY_KEY_ENV="${FACTORY_GATEWAY_KEY_ENV:-}"
  FACTORY_TEST_FILES_CMD=""
  # shellcheck source=/dev/null
  if [ -f .factory/commands.env ]; then . .factory/commands.env; fi
  FACTORY_LINT_CMD="${FACTORY_LINT_CMD:-}"; FACTORY_TEST_CMD="${FACTORY_TEST_CMD:-}"
  FACTORY_EXTRA_CMD="${FACTORY_EXTRA_CMD:-}"; FACTORY_GATEWAY_URL="${FACTORY_GATEWAY_URL:-}"
  FACTORY_HEALTH_CMD="${FACTORY_HEALTH_CMD:-}"; FACTORY_TEST_FILES_CMD="${FACTORY_TEST_FILES_CMD:-}"
}

# --- the right mission, on the right branch (D67) --------------------------------
# mission_guard <feature>: prints why the factory must not run this mission
# here and returns 1; silent and 0 when it may. Catches a misspelled name (it
# would start a new mission) and a checkout switched to another branch (by a
# person or another agent) while the mission's state lives elsewhere.
mission_guard() {
  local feature="$1" dir latest branch near
  dir="$(mission_dir "$feature")"
  if [ ! -d "$dir" ]; then
    near="$(ls -d "$FACTORY_DIR"/*/ 2>/dev/null | sed "s|^$FACTORY_DIR/||; s|/$||" | grep -vx light \
      | node -e '
        const want = process.argv[1], names = require("fs").readFileSync(0, "utf8").split("\n").filter(Boolean);
        const d = (a, b) => { const m = Array.from({ length: a.length + 1 }, (_, i) => [i]);
          for (let j = 1; j <= b.length; j++) m[0][j] = j;
          for (let i = 1; i <= a.length; i++) for (let j = 1; j <= b.length; j++)
            m[i][j] = Math.min(m[i-1][j] + 1, m[i][j-1] + 1, m[i-1][j-1] + (a[i-1] === b[j-1] ? 0 : 1));
          return m[a.length][b.length]; };
        const best = names.map((n) => [d(want.toLowerCase(), n.toLowerCase()), n]).sort((x, y) => x[0] - y[0])[0];
        if (best && best[0] <= Math.max(3, Math.floor(want.length / 4))) console.log(best[1]);' "$feature" 2>/dev/null || true)"
    if [ -n "$near" ]; then
      echo "no mission '$feature' in $FACTORY_DIR/. Did you mean '$near'? (a new mission with this name: mkdir -p $dir, then run again)"
      return 1
    fi
  fi
  latest="$(git log --exclude='pi-subagents/*' --branches -1 --format=%H -- "$dir" 2>/dev/null || true)"
  if [ -n "$latest" ] && ! git merge-base --is-ancestor "$latest" HEAD 2>/dev/null; then
    branch="$(git branch --contains "$latest" --format='%(refname:short)' 2>/dev/null | grep -v '^pi-subagents/' | head -1)"
    echo "the latest state of mission '$feature' ($(git rev-parse --short "$latest")) is on branch '${branch:-?}', not on '$(git branch --show-current)'. Switch back (git switch ${branch:-<branch>}); if another agent switched it, stash its changes first"
    return 1
  fi
  return 0
}

# require_mission <feature>: dies unless the mission exists here; a
# misspelled name gets the closest existing one (D67).
require_mission() {
  local why
  [ -f "$(mission_dir "$1")/spec.md" ] && return 0
  why="$(mission_guard "$1")" || die "$why"
  die "no mission '$1' in $FACTORY_DIR/ (no $(mission_dir "$1")/spec.md)"
}

# --- what the worktree hook adds (D65) ------------------------------------------
# Dependency links and .env.factory exist only in a worker's worktree. They
# never belong in a patch, and a link escapes a "node_modules/" ignore rule
# (that pattern matches directories, a link is a file). Pathspecs to exclude
# them; call after load_commands.
hook_excludes() {
  local n
  printf '%s\n' ':(exclude,glob)**/.env.factory'
  for n in ${FACTORY_DEPS_LINKS:-node_modules .venv}; do
    printf '%s\n' ":(exclude,glob)**/$n" ":(exclude,glob)**/$n/**"
  done
}

# --- lint against the baseline (D62) -------------------------------------------
# Legacy code often fails the team lint. The baseline, written by
# `health.sh baseline`, keeps the errors the code had then (one key per error,
# see lint-keys.mjs); a run passes when it adds none, whatever was there before.
FACTORY_LINT_BASELINE="${FACTORY_LINT_BASELINE:-.factory/lint-baseline.txt}"

lint_keys() {                          # <lint output file> → sorted keys
  node "$FACTORY_SCRIPTS/lint-keys.mjs" "$PWD" < "$1" | LC_ALL=C sort
}

# lint_new_errors <lint output file>: prints the errors not in the baseline.
lint_new_errors() {
  local base; base="$(mktemp)"
  if [ -f "$FACTORY_LINT_BASELINE" ]; then LC_ALL=C sort "$FACTORY_LINT_BASELINE" > "$base"; fi
  LC_ALL=C comm -23 <(lint_keys "$1") "$base"
  rm -f "$base"
}

# run_lint <output file>: 0 when FACTORY_LINT_CMD passes, or fails only on
# errors the baseline already has. A failing run with no recognizable error
# (a crash, a config error) fails: nothing proves it is old.
run_lint() {
  local out="$1" new
  bash -c "$FACTORY_LINT_CMD" > "$out" 2>&1 && return 0
  [ -f "$FACTORY_LINT_BASELINE" ] || { echo "lint failed and there is no $FACTORY_LINT_BASELINE (health.sh baseline writes it)" >> "$out"; return 1; }
  [ -n "$(lint_keys "$out")" ] || { echo "lint failed without a recognizable error line (FACTORY_LINT_ERROR_RE)" >> "$out"; return 1; }
  new="$(lint_new_errors "$out")"
  if [ -z "$new" ]; then echo "lint: only errors already in $FACTORY_LINT_BASELINE; passing (D62)" >> "$out"; return 0; fi
  { echo "lint: new errors (not in $FACTORY_LINT_BASELINE):"; printf '  %s\n' "$new"; } | tee -a "$out" >&2
  return 1
}

# --- humans: decisions, notifications (D43, D45) --------------------------------

# decision_log <feature> <ticket|-> <kind> <question> <answer> [scope] [who]
# One row per human decision in .scratch/<feature>/decisions.tsv. Status
# starts "unreviewed": only a human promotes a row into the spec or an ADR.
decision_log() {
  local f t who
  f="$(mission_dir "$1")/decisions.tsv"; mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || printf 'date\tticket\tkind\tquestion\tanswer\tscope\twho\tstatus\n' > "$f"
  who="${7:-$(git config user.name 2>/dev/null || echo human)}"
  t() { printf '%s' "$1" | tr '\t\n' '  '; }
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\tunreviewed\n' "$(date +%F)" "$(t "$2")" "$(t "$3")" \
    "$(t "$4")" "$(t "$5")" "$(t "${6:-ticket}")" "$(t "$who")" >> "$f"
}

notify() {                             # <title> <message>
  [ "${FACTORY_NOTIFY:-1}" = "0" ] && return 0
  if [ -n "${FACTORY_NOTIFY_CMD:-}" ]; then
    FACTORY_TITLE="$1" FACTORY_MESSAGE="$2" bash -c "$FACTORY_NOTIFY_CMD" >/dev/null 2>&1 || true
  elif command -v osascript >/dev/null 2>&1; then
    local t m; t="$(printf '%s' "$1" | tr -d '"\\')"; m="$(printf '%s' "$2" | tr -d '"\\')"
    osascript -e "display notification \"$m\" with title \"$t\"" >/dev/null 2>&1 || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "$1" "$2" >/dev/null 2>&1 || true
  else
    printf '\a' >&2
  fi
}


# --- hashing and briefs (D32) -------------------------------------------------

sha256() {                  # sha256 [file] — stdin when no file
  if command -v sha256sum >/dev/null; then sha256sum ${1:+"$1"}; else shasum -a 256 ${1:+"$1"}; fi
}

# brief_id <role> <scope> <ticket|-> <commit>: stable id recorded in verdicts.
brief_id() { printf '%s|%s|%s|%s' "$1" "$2" "$3" "$4" | sha256 "" | cut -c1-12; }

# --- mission diff (D49) -------------------------------------------------------

# The commit before the mission started: parent of the first commit that
# touched the mission directory. The steward and health check judge
# mission_base..HEAD, i.e. everything the mission changed.
mission_base() {
  local first
  first="$(git log --reverse --format=%H -- "$(mission_dir "$1")" | awk 'NR == 1')"
  [ -n "$first" ] || { git rev-parse HEAD; return 0; }
  git rev-parse "${first}^" 2>/dev/null || git rev-parse "$first"
}

is_code_file()  { [[ "$1" =~ $FACTORY_CODE_RE ]] && ! [[ "$1" =~ $FACTORY_EXCLUDE_RE ]]; }
is_test_file()  { [[ "$1" =~ $FACTORY_TEST_RE ]]; }

# Changed source files (not tests) between two commits, existing at the second.
changed_code_files() {                 # <base> <commit>
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    is_code_file "$f" && ! is_test_file "$f" && echo "$f"
  done < <(git diff --relative --name-only --diff-filter=ACMR "$1" "$2" -- . ":(exclude)${FACTORY_DIR}")
  return 0     # the last file being a test must not fail the caller under set -e
}

# --- test on base (D96) ---------------------------------------------------------
# A new test proves something only if it disagrees with the code before the
# change: in a feature or bugfix mission it must fail there (it tests what the
# ticket adds); in a maintenance or refactor mission it must pass there (it
# pins today's behavior). The patch's test files alone are applied to a
# temporary checkout of HEAD, the tests run, and the result is compared with
# what the intent expects. Call after load_commands, from the project folder.
#
# What runs (D101): with FACTORY_TEST_FILES_CMD (a command template holding
# {files}), only the patch's test files, so "must fail" is about them alone.
# Without it, a feature or bugfix first runs the whole suite on the base
# without the tests: if the base is already red, the new tests' failure proves
# nothing, so the check is inconclusive and the round fails ("base already
# red: set FACTORY_TEST_FILES_CMD"). Costs one or two extra test runs per
# ticket with tests.
#
# test_on_base <feature> <ticket> <project-relative patch> <log file> [base]
#   base: the commit the tests run on (default HEAD, the ticket's base at
#   integration and in a worker's worktree). Prints one line; returns 0 (as
#   expected, or not checked: off, no test command, no test files, another
#   intent), 1 (mismatch), 2 (error or inconclusive: the tests don't apply on
#   the base, the temporary worktree can't be made, the test command can't
#   start, the base is already red). Callers fail the round on 1 and 2.
#   A ticket opts out with "## Test on base: skip — <reason>": the line then
#   reads "test on base: skipped by the ticket (<reason>)".
# A subshell: its trap removes the temporary worktree on any exit or signal.
test_on_base() (
  feature="$1" ticket="$2" patch="$3" log="$4" base="${5:-HEAD}"
  dir="$(mission_dir "$feature")"
  if [ "${FACTORY_TEST_ON_BASE:-1}" = 0 ]; then echo "test on base: off (FACTORY_TEST_ON_BASE=0)"; exit 0; fi
  if [ -z "${FACTORY_TEST_CMD:-}" ]; then echo "test on base: no test command"; exit 0; fi
  intent="$(verdict_field "$dir/spec.md" Intent)"
  case "$intent" in
    feature|bugfix) want=fail ;;
    maintenance|refactor) want=pass ;;
    *) echo "test on base: not checked for intent '${intent:-none}'"; exit 0 ;;
  esac
  issue="$dir/issues/$ticket.md"
  if [ -f "$issue" ] && opt="$(grep -m1 -iE '^## Test on base: *skip' "$issue")"; then
    why="$(printf '%s' "$opt" | sed -E 's/^## [Tt]est on base: *[Ss]kip *(—|-|:)? *//')"
    echo "test on base: skipped by the ticket (${why:-no reason given})"; exit 0
  fi
  tmp="$(mktemp -d)"; wt="$tmp/wt"
  cleanup() {
    if [ -d "$wt" ]; then git worktree remove --force "$wt" >/dev/null 2>&1 || true; fi
    git worktree prune >/dev/null 2>&1 || true; rm -rf "$tmp"
  }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  while IFS=$'\x1f' read -r _ f n _; do
    for d in "$f" "$n"; do [ -n "$d" ] && is_test_file "$d" && printf '%s\n' "$d"; done
  done < <(node "$FACTORY_SCRIPTS/patch-paths.mjs" list "$patch") | sort -u > "$tmp/tests"
  if [ ! -s "$tmp/tests" ]; then echo "test on base: the change has no test files"; exit 0; fi
  node "$FACTORY_SCRIPTS/patch-paths.mjs" keep "$patch" "$tmp/tests.patch" "$tmp/tests"
  top="$(git rev-parse --show-toplevel)"; prefix="$(project_prefix)"
  # The instrument stays hidden, as in a worker's worktree (D21).
  if ! git worktree add -q --detach --no-checkout "$wt" "$base" >"$log" 2>&1; then
    echo "test on base: error: no temporary worktree at $base ($(tail -1 "$log"))"; exit 2
  fi
  git -C "$wt" sparse-checkout set --no-cone '/*' "!/${prefix:+$prefix/}${FACTORY_INSTRUMENT_DIR}/" >/dev/null 2>&1 || true
  if ! git -C "$wt" checkout -q --detach "$base" >"$log" 2>&1; then
    echo "test on base: error: can't check out $base in the temporary worktree ($(tail -1 "$log"))"; exit 2
  fi
  for d in ${prefix:+"$prefix"} ""; do           # the installed dependencies, as the worktree hook links them (D65)
    for n in ${FACTORY_DEPS_LINKS:-node_modules .venv}; do
      if [ -e "$top/${d:+$d/}$n" ] && [ ! -e "$wt/${d:+$d/}$n" ]; then ln -s "$top/${d:+$d/}$n" "$wt/${d:+$d/}$n"; fi
    done
  done
  # The command: the test files alone (FACTORY_TEST_FILES_CMD), else the suite.
  cmd="$FACTORY_TEST_CMD"
  if [ -n "${FACTORY_TEST_FILES_CMD:-}" ]; then
    files="$(while IFS= read -r f; do printf '%q ' "${f#"${prefix:+$prefix/}"}"; done < "$tmp/tests")"
    cmd="${FACTORY_TEST_FILES_CMD//\{files\}/${files% }}"
  elif [ "$want" = fail ]; then
    # Without the new tests, the base must be green, or their failure proves nothing.
    (cd "$wt/$prefix" && bash -c "$FACTORY_TEST_CMD") >"$log" 2>&1; rc=$?
    if [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; then echo "test on base: error: the test command can't start on $base (exit $rc)"; exit 2; fi
    if [ "$rc" -ne 0 ]; then
      echo "test on base: inconclusive: base already red: set FACTORY_TEST_FILES_CMD (the suite fails on $base without the new tests, so their failure proves nothing)"
      exit 2
    fi
  fi
  dirarg=(); [ -z "$prefix" ] || dirarg=(--directory="$prefix")
  if ! git -C "$wt" apply "${dirarg[@]}" "$tmp/tests.patch" >"$log" 2>&1; then
    echo "test on base: error: the tests don't apply on $base alone ($(tail -1 "$log"))"; exit 2
  fi
  (cd "$wt/$prefix" && bash -c "$cmd") >"$log" 2>&1; rc=$?
  if [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; then echo "test on base: error: the test command can't start on $base (exit $rc)"; exit 2; fi
  if [ "$want" = fail ] && [ "$rc" -eq 0 ]; then
    echo "test on base: the new tests pass on the code before the change ($intent mission): they don't test the ticket. Write a test that fails without the change, then make it pass"
    exit 1
  fi
  if [ "$want" = pass ] && [ "$rc" -ne 0 ]; then
    echo "test on base: the new tests fail on today's code ($intent mission): a characterization test must describe current behavior. Pin what the code does now"
    exit 1
  fi
  echo "test on base: as expected ($( [ "$want" = fail ] && echo "fails before the change" || echo "passes on today's code"))"
  exit 0
)

# --- ticket state (D33, D34) --------------------------------------------------
# Per ticket: built and integrated by integrate.sh (marker = integration
# commit), then reviewed. A verdict reviews one integration commit.
#   no marker, not passed          → build (if blockers passed)
#   marker, verdict missing/older  → review
#   verdict PASS                   → passed
#   verdict FAIL on that commit    → build again (fix round), or escalate

ticket_marker() {
  local f
  f="$(mission_dir "$1")/state/$2.integrated"
  if [ -f "$f" ]; then cat "$f"; fi
}

# Fills globals: T_PASSED (assoc num→1), T_BUILD, T_REVIEW, T_ESCALATE,
# T_BLOCKED (arrays of ticket names), T_ROUND (assoc name→last verdict round).
compute_ticket_state() {
  local feature="$1" dir t name num v r n marker vc b ready
  dir="$(mission_dir "$feature")"
  declare -gA T_PASSED=() T_ROUND=()
  T_BUILD=(); T_REVIEW=(); T_ESCALATE=(); T_BLOCKED=()
  shopt -s nullglob
  for t in "$dir"/issues/*.md; do
    name="$(ticket_name "$t")"; num="$(ticket_num "$t")"; v="$dir/verdicts/${name}-code.md"
    r="$(verdict_field "$v" Result)"; n="$(verdict_round "$v")"; T_ROUND[$name]="${n:-0}"
    [ "$r" = "PASS" ] && T_PASSED[$num]=1
  done
  for t in "$dir"/issues/*.md; do
    name="$(ticket_name "$t")"; num="$(ticket_num "$t")"
    [ -n "${T_PASSED[$num]:-}" ] && continue
    v="$dir/verdicts/${name}-code.md"; marker="$(ticket_marker "$feature" "$name")"
    vc="$(verdict_field "$v" Commit)"; n="${T_ROUND[$name]}"
    if [ -n "$marker" ] && [ "$vc" != "$marker" ]; then T_REVIEW+=("$name"); continue; fi
    if [ "$n" -ge "$FACTORY_ROUND_LIMIT" ] || [ -f "$dir/state/$name.stuck" ]; then T_ESCALATE+=("$name"); continue; fi
    ready=1
    for b in $(ticket_blockers "$t"); do
      [ "$b" = "$num" ] && continue
      [ -n "${T_PASSED[$b]:-}" ] || ready=0
    done
    if [ "$ready" -eq 1 ]; then T_BUILD+=("$name"); else T_BLOCKED+=("$name"); fi
  done
}

# --- provider errors (D58, D91) ------------------------------------------------
# A provider error, by its shape: an HTTP status next to a word that says so,
# or the providers' own wording. A "500" in a test name or a count is not one.
provider_error_line() {             # <text>: the line that shows a provider error, or nothing
  grep -Eio '(HTTP|status|error|code)[^0-9a-z]{0,3}(429|5[0-9][0-9])\b.*|\b(429|5[0-9][0-9]) (Too Many Requests|Internal Server Error|Bad Gateway|Service Unavailable|Gateway Timeout).*|rate.?limit(ed| exceeded| reached).*|(quota|insufficient_quota) (exceeded|reached).*|\boverloaded(_error)?\b.*' <<<"$1" | head -1 || true
}
