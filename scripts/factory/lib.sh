#!/usr/bin/env bash
# Shared helpers for the factory scripts. Sourced by next.sh, coverage.sh,
# gate.sh, workflow.sh, brief.sh, integrate.sh and the others. Formats are defined in docs/agents/*.md.
# Rationale for each rule: docs/adr/ADR-001-agentic-factory.md.

FACTORY_DIR="${FACTORY_DIR:-.scratch}"            # one path segment, no slash
FACTORY_ROUND_LIMIT="${FACTORY_ROUND_LIMIT:-3}"
FACTORY_BEHAVIOR_PATHS_FILE="${FACTORY_BEHAVIOR_PATHS_FILE:-.factory/behavior-paths}"
FACTORY_DOCS_RE="${FACTORY_DOCS_RE:-^(docs/|[^/]*\.md$)}"
FACTORY_INSTRUMENT_DIR="${FACTORY_INSTRUMENT_DIR:-instrument}"  # hidden from workers (D21)
FACTORY_MAX_PARALLEL="${FACTORY_MAX_PARALLEL:-4}"               # laptop-sized (D27)
FACTORY_SKILLS_DIR="${FACTORY_SKILLS_DIR:-.pi/skills}"          # pinned skills (D36)
FACTORY_BRIEFS_DIR="${FACTORY_BRIEFS_DIR:-.factory/briefs}"     # brief templates (D32)
FACTORY_AGENTS_DIR="${FACTORY_AGENTS_DIR:-.pi/agents/factory}"  # models live here (D31)
FACTORY_FIX_MAX_LINES="${FACTORY_FIX_MAX_LINES:-80}"            # fix-lane blast radius (D41)
FACTORY_HEALTH_BASELINE="${FACTORY_HEALTH_BASELINE:-.factory/health-baseline.json}"  # ratchet (D50)
# Source files the health checks and the steward look at (D49, D50).
FACTORY_CODE_RE="${FACTORY_CODE_RE:-\.(js|jsx|ts|tsx|mjs|cjs|py|go|java|kt|kts|rb|rs|cs|php|scala|swift|sh)$}"
FACTORY_TEST_RE="${FACTORY_TEST_RE:-(^|/)(tests?|__tests__|spec|specs)/|[._-](test|spec)\.[a-z]+$|_test\.(go|py)$}"
FACTORY_EXCLUDE_RE="${FACTORY_EXCLUDE_RE:-^(\.scratch|\.pi|\.factory|scripts/factory|instrument|node_modules|vendor|dist|build|coverage)/}"

die() { printf 'factory: %s\n' "$*" >&2; exit 2; }

mission_dir()  { printf '%s/%s' "$FACTORY_DIR" "$1"; }

# --- contract (spec.md) ------------------------------------------------------

has_contract() { grep -q '^## Validation contract' "$1"; }

contract_approved() {
  grep -qE '^\*\*Contract approved:\*\* [0-9]{4}-[0-9]{2}-[0-9]{2}' "$1"
}

# Active assertion IDs. Withdrawn ones are written "### ~~VAL-…~~" and skipped.
contract_ids() {
  awk '
    /^## Validation contract/ { in_c = 1; next }
    in_c && /^## /            { in_c = 0 }
    in_c && /^### VAL-[A-Z0-9]+-[0-9][0-9][0-9]:/ {
      id = $2; sub(/:$/, "", id); print id
    }' "$1"
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

# The model a factory agent is configured with (frontmatter). Verdicts carry
# this, never the model's own guess about itself (D39).
agent_model() {                        # <agent name>
  local f="$FACTORY_AGENTS_DIR/$1.md"
  [ -f "$f" ] || { echo "unknown"; return 0; }
  awk '/^---$/ { c++; next } c == 1 && /^model:/ { sub(/^model:[ \t]*/, ""); print; exit }' "$f"
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
  [ -z "$(git diff --name-only "$sha" HEAD -- . ":(exclude)${FACTORY_DIR}")" ]
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
  changed="$(git diff --name-only "$sha" HEAD -- . ":(exclude)${FACTORY_DIR}")"
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
  done < <(git diff --name-only "$sha" HEAD -- . ":(exclude)${FACTORY_DIR}")
  return 0
}

# --- commands.env (D8, D34) ---------------------------------------------------

load_commands() {
  FACTORY_LINT_CMD=""; FACTORY_TEST_CMD=""; FACTORY_EXTRA_CMD=""; FACTORY_GATEWAY_URL=""; FACTORY_HEALTH_CMD=""
  # shellcheck source=/dev/null
  if [ -f .factory/commands.env ]; then . .factory/commands.env; fi
  FACTORY_LINT_CMD="${FACTORY_LINT_CMD:-}"; FACTORY_TEST_CMD="${FACTORY_TEST_CMD:-}"
  FACTORY_EXTRA_CMD="${FACTORY_EXTRA_CMD:-}"; FACTORY_GATEWAY_URL="${FACTORY_GATEWAY_URL:-}"
  FACTORY_HEALTH_CMD="${FACTORY_HEALTH_CMD:-}"
}

# --- humans: decisions, notifications (D43, D45) --------------------------------

# decision_log <feature> <ticket|-> <kind> <question> <answer> [scope]
# One row per human decision in .scratch/<feature>/decisions.tsv. Status
# starts "unreviewed": only a human promotes a row into the spec or an ADR.
decision_log() {
  local f t who
  f="$(mission_dir "$1")/decisions.tsv"; mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || printf 'date\tticket\tkind\tquestion\tanswer\tscope\twho\tstatus\n' > "$f"
  who="$(git config user.name 2>/dev/null || echo human)"
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
  done < <(git diff --name-only --diff-filter=ACMR "$1" "$2" -- . ":(exclude)${FACTORY_DIR}")
}

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
    if [ "$n" -ge "$FACTORY_ROUND_LIMIT" ]; then T_ESCALATE+=("$name"); continue; fi
    ready=1
    for b in $(ticket_blockers "$t"); do
      [ "$b" = "$num" ] && continue
      [ -n "${T_PASSED[$b]:-}" ] || ready=0
    done
    if [ "$ready" -eq 1 ]; then T_BUILD+=("$name"); else T_BLOCKED+=("$name"); fi
  done
}
