#!/usr/bin/env bash
# The benchmark from our own tickets (D98, proposal P14). A case is a ticket
# the factory really did; a run replays it with another model setup, scored by
# the gates integration uses. Nothing touches the real branch: each case runs
# in a throwaway worktree in the git folder, and nothing is pushed.
#
# Usage:
#   bench.sh add <mission> <ticket> [--why "..."] [--difficulty easy|medium|hard|extra-hard]
#                [--area <tag>] [--role worker] [--suite <name>] [--kind regression|followup]
#   bench.sh add-file <issue.md> <mission> [--area <tag>] [--suite <name>] [--why "..."]
#                a hand-written follow-up case (kind followup)
#   bench.sh list [suite]
#   bench.sh run <suite|all> --config <models-profile.json> [--label x] [--review]
#                [--case <id>] [--debug]
#   bench.sh probe <suite|all> --config <profile> [--at <commit>] [--label x]
#                follow-up cases on the code at <commit> (default HEAD): how
#                easy the code left behind is to change
#   bench.sh compare <label> <label>... [--default <label>] [--strict] [--name x]
#   bench.sh paired --a <label,label…> --b <label,label…> [--json]
#                the same cases under two arms (repeats pooled): per-case deltas,
#                median change with a bootstrap 95% CI, McNemar on pass/fail.
#                To compare factory versions, run one arm with an older
#                version's briefs: FACTORY_BRIEFS_DIR=<dir> bench.sh run …
#
# Files (committed with the project's factory data):
#   .factory/bench/cases.tsv               one line per case
#   .factory/bench/cases/<id>/             issue.md, spec.md, case.json: all a run needs
#   .factory/bench/results/<label>.tsv     one line per case run
#   .factory/bench/results/<label>.json    the configuration and the summary
#   .factory/bench/compare/<name>.json     what the cockpit's Benchmarks view reads
#
# Runner: FACTORY_BENCH_RUNNER, a command called as
#   <runner> <role> <case-id> <work-dir> <brief-file> <model> <thinking> <out-dir>
# that does the role's work in <work-dir> and may write <out-dir>/usage.json
# ({ "turns", "input", "output", "cost" }). Unset: pi in JSON mode with the
# driver (as run.sh does), the role's model and thinking set as project
# agentOverrides in the throwaway worktree.
#
# Guarded like workers (D101): agents run with FACTORY_ROLE=worker, so the
# factory guard applies the worker rules (no network, no shared dependencies);
# a case worktree without .pi/extensions/factory-guard.ts is refused, never
# run unguarded. Pi loads project extensions only for a trusted project: trust
# this repo in Pi once (pi asks the first time it starts here) before a run.
# Case worktrees are removed on any exit, error or interrupt, unless --debug.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

BENCH="${FACTORY_BENCH_DIR:-.factory/bench}"
CASES="$BENCH/cases.tsv"
HEADER=$'id\tmission\tticket\tsuite\tkind\trole\tdifficulty\tarea\tbase\trounds\tfirst_pass\tescalated\twhy'
cmd="${1:-}"; shift || true

ensure_cases() { mkdir -p "$BENCH/cases"; [ -f "$CASES" ] || printf '%s\n' "$HEADER" > "$CASES"; }
case_field() {   # case_field <id> <column name>
  awk -F'\t' -v id="$1" -v col="$2" 'NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next } $1 == id { print $h[col]; exit }' "$CASES"
}
difficulty_of() {   # <rounds> <first_pass> <escalated>
  if [ "$3" = yes ]; then echo extra-hard; elif [ "$2" = yes ]; then echo easy
  elif [ "${1:-1}" -le 2 ]; then echo medium; else echo hard; fi
}
sha_of() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -c1-12; else shasum -a 256 "$1" | cut -c1-12; fi; }

# --- add ---------------------------------------------------------------------
add_case() {    # <id> <mission> <ticket> <suite> <kind> <role> <difficulty> <area> <base> <rounds> <first> <esc> <why> <issue> <spec>
  local id="$1" d="$BENCH/cases/$1"
  ensure_cases
  awk -F'\t' -v id="$id" 'NR > 1 && $1 == id { found = 1 } END { exit !found }' "$CASES" && die "case $id exists already"
  mkdir -p "$d"
  cp "${14}" "$d/issue.md"; cp "${15}" "$d/spec.md"
  node -e 'const [id,mission,ticket,suite,kind,role,difficulty,area,base,rounds,first,esc,why,sha,out]=process.argv.slice(1);
    require("fs").writeFileSync(out, JSON.stringify({id,mission,ticket,suite,kind,role,difficulty,area,base,
      outcome:{rounds:Number(rounds)||0,first_pass:first==="yes",escalated:esc==="yes"},why,issue_sha:sha}, null, 2)+"\n")' \
    "$id" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" "${13}" "$(sha_of "$d/issue.md")" "$d/case.json"
  printf '%s\n' "$id" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" "${13//$'\t'/ }" | paste -sd$'\t' - >> "$CASES"
  echo "bench: case $id added ($5, $6, $7${8:+, $8}; base ${9:0:12})"
}

do_add() {
  local mission="${1:?usage: bench.sh add <mission> <ticket> [options]}" ticket="${2:?usage: bench.sh add <mission> <ticket> [options]}"
  shift 2
  local why="" difficulty="" area="" role="worker" suite="default" kind="regression"
  while [ $# -gt 0 ]; do case "$1" in
    --why) why="${2:?}"; shift ;; --difficulty) difficulty="${2:?}"; shift ;;
    --area) area="${2:?}"; shift ;; --role) role="${2:?}"; shift ;;
    --suite) suite="${2:?}"; shift ;; --kind) kind="${2:?}"; shift ;;
    *) die "unknown option: $1" ;; esac; shift; done
  case "$difficulty" in ""|easy|medium|hard|extra-hard) ;; *) die "difficulty: easy, medium, hard or extra-hard" ;; esac
  case "$kind" in regression|followup) ;; *) die "kind: regression or followup" ;; esac
  local dir issue spec v rounds first=no esc=no base first_int
  dir="$(mission_dir "$mission")"; issue="$dir/issues/$ticket.md"; spec="$dir/spec.md"
  [ -f "$issue" ] || die "no ticket $ticket in $mission ($issue)"
  v="$dir/verdicts/$ticket-code.md"
  rounds="$(verdict_round "$v")"; rounds="${rounds:-0}"
  local r1="${v%.md}.r1.md"; [ -f "$r1" ] || r1="$v"
  [ "$(verdict_field "$r1" Result)" = PASS ] && first=yes
  if [ -f "$dir/state/$ticket.stuck" ] || { [ "$rounds" -ge "$FACTORY_ROUND_LIMIT" ] && [ "$(verdict_field "$v" Result)" != PASS ]; }; then esc=yes; fi
  # The case starts where the worker started: the commit before the ticket's
  # first integration (integrate.sh commits "<type>(<mission>): <ticket>").
  first_int="$(git log --reverse --format='%H%x09%s' | awk -F'\t' -v s="($mission): $ticket" \
    '{ i = index($2, s) } i > 1 && i + length(s) - 1 == length($2) && substr($2, 1, i - 1) ~ /^[a-z]+$/ { print $1; exit }')"
  [ -n "$first_int" ] || first_int="$(ticket_marker "$mission" "$ticket")"
  if [ "$kind" = regression ]; then
    [ -n "$first_int" ] || die "$ticket was never integrated: nothing to replay (a hand-written follow-up goes in with add-file)"
    base="$(git rev-parse "$first_int^")"
  else
    base="-"
  fi
  [ -n "$difficulty" ] || difficulty="$(difficulty_of "$rounds" "$first" "$esc")"
  add_case "$mission--$ticket" "$mission" "$ticket" "$suite" "$kind" "$role" "$difficulty" "$area" "$base" "$rounds" "$first" "$esc" "$why" "$issue" "$spec"
}

do_add_file() {
  local file="${1:?usage: bench.sh add-file <issue.md> <mission> [options]}" mission="${2:?usage: bench.sh add-file <issue.md> <mission> [options]}"
  shift 2
  local why="" area="" suite="default" difficulty="medium" role="worker"
  while [ $# -gt 0 ]; do case "$1" in
    --why) why="${2:?}"; shift ;; --area) area="${2:?}"; shift ;; --suite) suite="${2:?}"; shift ;;
    --difficulty) difficulty="${2:?}"; shift ;; --role) role="${2:?}"; shift ;;
    *) die "unknown option: $1" ;; esac; shift; done
  [ -f "$file" ] || die "no file $file"
  local spec; spec="$(mission_dir "$mission")/spec.md"; [ -f "$spec" ] || die "no mission $mission"
  local ticket; ticket="$(basename "$file" .md)"
  add_case "$mission--$ticket" "$mission" "$ticket" "$suite" followup "$role" "$difficulty" "$area" - 0 no no "$why" "$file" "$spec"
}

# --- run ---------------------------------------------------------------------
# select_cases <suite|all> <kind filter: regression|followup|any> [case id]
select_cases() {
  [ -f "$CASES" ] || die "no cases yet: bench.sh add <mission> <ticket>"
  awk -F'\t' -v s="$1" -v k="$2" -v c="${3:-}" 'NR > 1 && (s == "all" || $4 == s) && (k == "any" || $5 == k) && (c == "" || $1 == c) { print $1 }' "$CASES"
}

profile_role() {   # <profile> <role> → "model<TAB>thinking"
  node -e 'const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const a=(p.agents||{})["factory-"+process.argv[2]]||{};
    process.stdout.write((a.model||"")+"\t"+(a.thinking||""))' "$1" "$2"
}

# The current case's worktree, removed on any exit or signal unless --debug (D101).
BENCH_WT=""; BENCH_TOP=""; BENCH_KEEP=0
bench_cleanup() {
  [ -n "$BENCH_WT" ] || return 0
  if [ "$BENCH_KEEP" = 1 ]; then echo "bench: kept $BENCH_WT" >&2
  else git -C "$BENCH_TOP" worktree remove --force "$BENCH_WT" >/dev/null 2>&1 || rm -rf "$BENCH_WT"
    git -C "$BENCH_TOP" worktree prune >/dev/null 2>&1 || true; fi
  BENCH_WT=""
}
trap bench_cleanup EXIT
trap 'bench_cleanup; exit 130' INT
trap 'bench_cleanup; exit 143' TERM

pi_runner() {      # same arguments as FACTORY_BENCH_RUNNER
  local role="$1" id="$2" wd="$3" brief="$4" model="$5" thinking="$6" out="$7" wf raw
  read -r -a pi_cmd <<<"${FACTORY_PI_CMD:-pi}"; [ -z "${FACTORY_PI_BIN:-}" ] || pi_cmd=("$FACTORY_PI_BIN")
  # The factory guard admits workflows from a mission's workflows folder (D71).
  wf=".scratch/$(case_field "$id" mission)/workflows/bench-$role.js"
  mkdir -p "$wd/$(dirname "$wf")"
  node -e 'const fs=require("fs");const [file,agent,brief]=process.argv.slice(1);
    fs.writeFileSync(file, "// bench.sh (D98)\nconst r = await runs.run(\"bench\", { agent: "+JSON.stringify(agent)+", task: "+JSON.stringify(fs.readFileSync(brief,"utf8"))+" });\nreturn { output: r?.output ?? null, usage: r?.results?.[0]?.usage ?? r?.usage ?? null };\n")' \
    "$wd/$wf" "factory-$role" "$brief"
  node -e 'const fs=require("fs");const f=process.argv[1];const s=fs.existsSync(f)?JSON.parse(fs.readFileSync(f,"utf8")):{};
    s.subagents=s.subagents||{};s.subagents.agentOverrides=s.subagents.agentOverrides||{};
    const o={};if(process.argv[3])o.model=process.argv[3];if(process.argv[4])o.thinking=process.argv[4];
    s.subagents.agentOverrides["factory-"+process.argv[2]]=Object.assign(s.subagents.agentOverrides["factory-"+process.argv[2]]||{},o);
    fs.mkdirSync(require("path").dirname(f),{recursive:true});fs.writeFileSync(f,JSON.stringify(s,null,2))' "$wd/.pi/settings.json" "$role" "$model" "$thinking"
  raw="$out/pi.jsonl"
  ( cd "$wd" && FACTORY_ROLE=worker FACTORY_DRIVE_WORKFLOW="./$wf" "${pi_cmd[@]}" -p --mode json --no-session --approve \
      -e "$here/driver.mjs" --model factory-driver/script "run the workflow" </dev/null >"$raw" 2>"$raw.err" ) || true
  node -e 'const fs=require("fs");const lines=fs.readFileSync(process.argv[1],"utf8").split("\n").filter(Boolean);let end=null;
    for(const l of lines){try{const e=JSON.parse(l);if(e.type==="tool_execution_end"&&e.toolName==="subagent")end=e;}catch{}}
    const v=end?.result?.details?.workflow?.value; const u=v?.usage||{};
    fs.writeFileSync(process.argv[2],JSON.stringify({turns:u.turns||0,input:u.input||0,output:u.output||0,cost:u.cost||0,ok:!!v}));
    process.exit(v?0:1)' "$raw" "$out/usage.json"
}

run_role() {       # <role> <id> <wd> <brief> <profile> <out>
  local mt model thinking
  mt="$(profile_role "$5" "$1")"; model="${mt%%$'\t'*}"; thinking="${mt#*$'\t'}"
  if [ -n "${FACTORY_BENCH_RUNNER:-}" ]; then
    FACTORY_ROLE=worker "$FACTORY_BENCH_RUNNER" "$1" "$2" "$3" "$4" "$model" "$thinking" "$6"
  else
    pi_runner "$1" "$2" "$3" "$4" "$model" "$thinking" "$6"
  fi
}

# one_case <id> <profile> <label> <at-commit or empty> <review 0|1> <debug 0|1> → one TSV line
one_case() {
  local id="$1" profile="$2" label="$3" at="$4" review="$5" debug="$6"
  local mission ticket kind role base d top prefix wt wd out start rc=0 gate="" patch
  mission="$(case_field "$id" mission)"; ticket="$(case_field "$id" ticket)"; kind="$(case_field "$id" kind)"
  role="$(case_field "$id" role)"; base="$(case_field "$id" base)"; d="$BENCH/cases/$id"
  [ -n "$at" ] && base="$(git rev-parse "$at")"
  [ "$base" != "-" ] || base="$(git rev-parse HEAD)"
  top="$(git rev-parse --show-toplevel)"; prefix="$(project_prefix)"
  local root; root="$(git rev-parse --path-format=absolute --git-common-dir)/pi-factory/bench"
  wt="$root/wt-$label-$id-$$"; out="$root/out/$label/$id"; rm -rf "$out"; mkdir -p "$out"
  git -C "$top" worktree add -q --detach "$wt" "$base" >/dev/null 2>&1 || die "could not create a worktree at $base"
  BENCH_WT="$wt"; BENCH_TOP="$top"; BENCH_KEEP="$debug"
  wd="$wt${prefix:+/$prefix}"
  # D101: never an unguarded agent.
  [ -f "$wd/.pi/extensions/factory-guard.ts" ] || [ -f "$wt/.pi/extensions/factory-guard.ts" ] \
    || die "case $id: no .pi/extensions/factory-guard.ts at $base: bench won't run agents without the factory guard"
  # The worktree gets what a worker's would (D21, D27, D65): instrument hidden,
  # its port, the dependencies linked.
  printf '{"repoRoot":"%s","worktreePath":"%s","agentCwd":"%s","index":0}' "$top" "$wt" "$wd" \
    | FACTORY_PROJECT_PREFIX="$prefix" node "$here/worktree-hook.mjs" >/dev/null 2>&1 || true
  # The case, as round 1: its issue and spec, no verdict or journal from later rounds.
  local md="$wd/$FACTORY_DIR/$mission"
  mkdir -p "$md/issues"; cp "$d/issue.md" "$md/issues/$ticket.md"; cp "$d/spec.md" "$md/spec.md"
  rm -f "$md/verdicts/$ticket-code"*.md "$md/journal/$ticket.md" "$md/state/$ticket".*
  # Today's commands and baselines decide, as integration would today.
  mkdir -p "$wd/.factory"
  for f in .factory/commands.env "$FACTORY_LINT_BASELINE"; do [ -f "$f" ] && cp "$f" "$wd/$f"; done
  # Today's briefs, unless the run compares factory versions on purpose.
  local briefs; briefs="$(cd "$(factory_res "$FACTORY_BRIEFS_DIR")" && pwd)"
  ( cd "$wd" && FACTORY_BRIEFS_DIR="$briefs" bash "$here/brief.sh" "$role" "$mission" "$ticket" "$base" ) > "$out/brief.md"
  start="$(date +%s)"
  run_role "$role" "$id" "$wd" "$out/brief.md" "$profile" "$out" > "$out/runner.log" 2>&1 || rc=$?
  patch="$out/change.patch"
  local skip=(); mapfile -t skip < <(load_commands; hook_excludes)
  ( cd "$wd" && git add -A -- . ":(exclude)$FACTORY_DIR" "${skip[@]}" >/dev/null 2>&1 \
      && git diff --cached --relative --binary "$base" -- . ":(exclude)$FACTORY_DIR" > "$patch" ) || true
  if [ "$rc" -ne 0 ] && [ ! -s "$patch" ]; then gate=runner
  elif [ ! -s "$patch" ]; then gate=no-patch
  elif ! ( cd "$wd" && bash "$here/patch-guard.sh" "$patch" --mission "$mission" ) > "$out/guard.log" 2>&1; then gate=guard
  else
    ( cd "$wd" && load_commands
      if [ -n "$FACTORY_LINT_CMD" ]; then run_lint "$PWD/.bench-lint.log" || { cat .bench-lint.log; exit 11; }; fi
      if [ -n "$FACTORY_TEST_CMD" ]; then bash -c "$FACTORY_TEST_CMD" || exit 12; fi
      exit 0 ) > "$out/checks.log" 2>&1 || rc=$?
    case "$rc" in 11) gate=lint ;; 12) gate=tests ;; esac
    # The test-on-base check (D96), when this factory has it.
    if [ -z "$gate" ] && [ -f "$here/test-on-base.sh" ]; then
      ( cd "$wd" && bash "$here/test-on-base.sh" "$mission" "$ticket" "$patch" "$base" ) > "$out/test-on-base.log" 2>&1 || gate=test-on-base
    fi
    if [ -z "$gate" ] && [ "$review" = 1 ]; then
      ( cd "$wd" && git -c user.name=bench -c user.email=bench@localhost commit -q -m "bench: $id" -- . ":(exclude)$FACTORY_DIR" >/dev/null 2>&1 || true
        bash "$here/brief.sh" reviewer "$mission" "$ticket" "$(git rev-parse HEAD)" ) > "$out/review-brief.md" 2>/dev/null || true
      mkdir -p "$out/review"
      run_role reviewer "$id" "$wd" "$out/review-brief.md" "$profile" "$out/review" > "$out/review/runner.log" 2>&1 || true
      [ "$(verdict_field "$md/verdicts/$ticket-code.md" Result)" = PASS ] || gate=review
    fi
  fi
  local secs=$(( $(date +%s) - start )) turns=0 tokens=0 cost=0
  if [ -f "$out/usage.json" ]; then
    read -r turns tokens cost < <(node -e 'const u=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
      console.log((u.turns||0)+" "+((u.input||0)+(u.output||0))+" "+(u.cost||0))' "$out/usage.json")
  fi
  if [ "$debug" = 1 ]; then echo "bench: kept $wd (transcript and logs: $out)" >&2; BENCH_WT=""
  else bench_cleanup; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t1\n' "$id" "$(case_field "$id" difficulty)" "$(case_field "$id" area)" \
    "$([ -z "$gate" ] && echo yes || echo no)" "${gate:--}" "$turns" "$tokens" "$cost" "$secs"
}

do_run() {     # <probe 0|1> <suite> options...
  local probe="$1" suite="${2:?usage: bench.sh run <suite|all> --config <profile> [options]}"; shift 2
  local profile="" label="" review=0 only="" debug=0 at=""
  while [ $# -gt 0 ]; do case "$1" in
    --config) profile="${2:?}"; shift ;; --label) label="${2:?}"; shift ;;
    --review) review=1 ;; --case) only="${2:?}"; shift ;; --debug) debug=1 ;;
    --at) at="${2:?}"; shift ;;
    *) die "unknown option: $1" ;; esac; shift; done
  [ -f "$profile" ] || die "--config <models-profile.json> is required (the models per role for this run)"
  local kind=regression; [ "$probe" = 1 ] && { kind=followup; at="${at:-HEAD}"; }
  [ -n "$label" ] || label="$( [ "$probe" = 1 ] && echo "probe-$(git rev-parse --short "$at")-" )$(basename "$profile" .json)"
  case "$label" in */*|.*) die "label: a plain name" ;; esac
  local ids; ids="$(select_cases "$suite" "$kind" "$only")"
  [ -n "$ids" ] || die "no $kind case in suite '$suite'${only:+ with id $only}"
  load_commands
  mkdir -p "$BENCH/results"
  local res="$BENCH/results/$label.tsv"
  printf 'case\tdifficulty\tarea\tpass\tfailed_gate\tturns\ttokens\tcost\tseconds\trounds\n' > "$res"
  local id
  for id in $ids; do
    echo "bench: $id ($label)" >&2
    one_case "$id" "$profile" "$label" "$at" "$review" "$debug" >> "$res"
  done
  node "$here/bench-report.mjs" summary "$res" "$profile" "$suite" "$label" "${at:+$(git rev-parse "$at")}" "$probe" \
    "$(cat .factory/VERSION 2>/dev/null || echo unknown)" "$(cat "$FACTORY_BRIEFS_DIR"/*.md 2>/dev/null | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-12)" \
    > "$BENCH/results/$label.json"
  node "$here/bench-report.mjs" print "$BENCH/results/$label.json"
}

case "$cmd" in
  add) do_add "$@" ;;
  add-file) do_add_file "$@" ;;
  list) [ -f "$CASES" ] || die "no cases yet"; awk -F'\t' -v s="${1:-all}" 'NR == 1 || s == "all" || $4 == s' "$CASES" | column -ts$'\t' ;;
  run) do_run 0 "$@" ;;
  probe) do_run 1 "$@" ;;
  compare)
    mkdir -p "$BENCH/compare"
    node "$here/bench-report.mjs" compare "$BENCH" "$@" ;;
  paired)
    node "$here/bench-report.mjs" paired "$BENCH" "$@" ;;
  ""|-h|--help|help) sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $cmd (bench.sh help)" ;;
esac
