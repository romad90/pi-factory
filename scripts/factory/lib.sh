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

verdict_round() {
  [ -f "$1" ] || return 0
  { grep -m1 -oE 'round [0-9]+' "$1" || true; } | awk '{print $2}'
}

# A verdict is fresh when no file outside the missions dir changed
# between the commit it was produced on and HEAD.
verdict_is_fresh() {
  local sha="$1"
  [ -n "$sha" ] || return 1
  git cat-file -e "${sha}^{commit}" 2>/dev/null || return 1
  [ -z "$(git diff --name-only "$sha" HEAD -- . ":(exclude)${FACTORY_DIR}")" ]
}


# --- hashing and briefs (D32) -------------------------------------------------

sha256() {                  # sha256 [file] — stdin when no file
  if command -v sha256sum >/dev/null; then sha256sum ${1:+"$1"}; else shasum -a 256 ${1:+"$1"}; fi
}

# brief_id <role> <scope> <ticket|-> <commit>: stable id recorded in verdicts.
brief_id() { printf '%s|%s|%s|%s' "$1" "$2" "$3" "$4" | sha256 "" | cut -c1-12; }

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
