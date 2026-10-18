#!/usr/bin/env bash
# One-word human gates (D43). Each command writes the line a human used to
# type by hand, logs it to .scratch/<feature>/decisions.tsv, and checkpoints.
# The lead runs them through /factory-approve, /factory-decide, /factory-amend.
#
# Usage:
#   human.sh approve           <feature> [note]        G1: the contract
#   human.sh approve           <feature> tickets       the tickets the ticket writer proposed
#   human.sh ask               <feature> <ticket|-> <question>      (lead, when relaying)
#   human.sh ask               <feature> <ticket|-> --stdin < question
#   human.sh decide            <feature> <answer> [why...]
#   human.sh decide            <feature> --stdin < answer-and-why
# --stdin reads the text verbatim (D68): the lead passes it in a quoted
# heredoc, so backticks, $ and quotes in a question or answer stay text.
#   human.sh amend             <feature> <change...>
#   human.sh accept-unverified <feature> <VAL-…,VAL-…|ALL> <why...>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

cmd="${1:?usage: human.sh <approve|ask|decide|amend|accept-unverified> <feature> ...}"
feature="${2:?usage: human.sh $cmd <feature> ...}"
shift 2
dir="$(mission_dir "$feature")"; spec="$dir/spec.md"
[ -f "$spec" ] || die "no spec at $spec"
q="$dir/state/open-question.md"

# The text argument(s), or stdin with --stdin; newlines become spaces.
text_arg() {                           # <args...>
  if [ "${1:-}" = --stdin ]; then tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//'
  else printf '%s' "$*"; fi
}

# Insert or replace a "**Label:** value" line right under the contract heading.
set_contract_line() {                  # <label> <value>
  local tmp; tmp="$(mktemp)"
  awk -v label="$1" -v value="$2" '
    index($0, "**" label ":**") == 1 { next }
    { print }
    /^## Validation contract/ && !done { print ""; print "**" label ":** " value; done = 1 }' "$spec" > "$tmp"
  mv "$tmp" "$spec"
}

case "$cmd" in
  approve)
    if [ "${1:-}" = tickets ]; then
      [ -f "$dir/state/tickets.pending" ] || die "no tickets waiting for approval"
      task="$(verdict_field "$dir/state/tickets.pending" Task)"
      rm -f "$dir/state/tickets.pending"
      shopt -s nullglob; list=("$dir"/issues/*.md)
      decision_log "$feature" - approve-tickets "Approve the tickets ($task)" "approved: ${#list[@]} ticket(s)" tickets
      bash "$here/checkpoint.sh" "$feature" >/dev/null
      echo "Tickets approved (${#list[@]} in issues/). Coverage (G2) runs next."
      exit 0
    fi
    has_contract "$spec" || die "no validation contract in $spec yet"
    if [ -f "$dir/contract-critique.md" ] && grep -q '\[blocking\]' "$dir/contract-critique.md"; then
      echo "Note: the critique still lists [blocking] findings. Approving means you accept them as they are."
    fi
    set_contract_line "Contract approved" "$(date +%F)${1:+ — $*}"
    decision_log "$feature" - approve "G1: approve the validation contract" "approved" contract
    echo "G1 approved."
    ;;

  ask)
    ticket="${1:?usage: human.sh ask <feature> <ticket|-> <question>}"; shift
    question="$(text_arg "$@")"
    [ -n "$question" ] || die "usage: human.sh ask <feature> <ticket|-> <question> (or --stdin)"
    # D70: a settled question is answered here, logged as "auto", and the
    # ticket rebuilds with the answer in decisions.tsv; the human can overturn it.
    if [ "${FACTORY_RESOLVER:-1}" != 0 ] && settled="$(bash "$here/resolve.sh" "$feature" "$ticket" "$question")"; then
      rule="${settled%%$'\t'*}"; auto="${settled#*$'\t'}"
      decision_log "$feature" "$ticket" auto "$question" "$auto" ticket "factory ($rule)"
      bash "$here/checkpoint.sh" "$feature" >/dev/null
      echo "AUTO-ANSWERED ($rule): $auto"
      echo "Logged in $(mission_dir "$feature")/decisions.tsv as auto, unreviewed. Continue: the ticket rebuilds with the answer."
      exit 0
    fi
    asked=0
    [ -f "$dir/decisions.tsv" ] && asked="$(awk -F'\t' -v t="$ticket" 'NR > 1 && $2 == t && ($3 == "decide" || $3 == "auto")' "$dir/decisions.tsv" | wc -l | tr -d ' ')"
    mkdir -p "$dir/state"
    { printf '**Ticket:** %s\n**Asked:** %s\n\n%s\n' "$ticket" "$(date '+%F %H:%M')" "$question"
      if [ "$asked" -ge 2 ]; then
        printf '\nQuestion %s on %s. Several questions on one ticket usually mean it is too big or underspecified: you can also answer by shrinking it (split it, or move assertions to another ticket), or reset it (scripts/factory/reset-ticket.sh %s %s).\n' \
          "$((asked + 1))" "$ticket" "$feature" "$ticket"
      fi; } > "$q"
    notify "Factory: $feature needs a decision" "$question"
    echo "ASKED: question recorded in $q. Answer with: /factory-decide $feature <your answer, and why>"
    ;;

  decide)
    if [ "${1:-}" = --stdin ]; then answer="$(text_arg --stdin)"; set --
    else answer="${1:-}"; shift || true; fi
    [ -n "$answer" ] || die "usage: human.sh decide <feature> <answer> [why...] (or --stdin)"
    ticket="-"; question="(no recorded question)"
    if [ -f "$q" ]; then
      ticket="$(verdict_field "$q" Ticket)"
      question="$(awk 'NR > 3 && /^$/ { exit } NR > 3' "$q" | tr '\n' ' ' | sed 's/ *$//')"
      rm -f "$q"
    fi
    decision_log "$feature" "${ticket:--}" decide "$question" "$answer${1:+ — $*}" ticket
    echo "Decision logged in $dir/decisions.tsv. Briefs list that file, so the next run reads it."
    ;;

  amend)
    [ $# -gt 0 ] || die "usage: human.sh amend <feature> <change...>"
    mkdir -p "$dir/amendments"
    a="$dir/amendments/$(date +%Y%m%d-%H%M%S).md"
    printf '# Amendment request\n**Status:** pending\n**Requested:** %s\n\n%s\n' "$(date +%F)" "$*" > "$a"
    tmp="$(mktemp)"; grep -v '^\*\*Contract approved:\*\*' "$spec" > "$tmp"; mv "$tmp" "$spec"
    decision_log "$feature" - amend "Amend the contract" "$*" contract
    echo "Amendment recorded ($a). Approval removed: the contract wave rewrites, the critic re-reads, you approve again."
    ;;

  accept-unverified)
    ids="${1:?usage: human.sh accept-unverified <feature> <VAL-…,…|ALL> <why...>}"; shift
    [ $# -gt 0 ] || die "say why these assertions can ship unverified"
    ids="$(printf '%s' "$ids" | tr ',' ' ' | xargs | sed 's/ /, /g')"
    set_contract_line "Accepted unverified" "$(date +%F) $ids — $*"
    decision_log "$feature" - accept-unverified "Ship with unverified assertions?" "$ids — $*" contract
    echo "Accepted unverified: $ids. The MR shows them as Known limits."
    ;;

  *) die "unknown command: $cmd" ;;
esac
bash "$here/checkpoint.sh" "$feature" >/dev/null
