#!/usr/bin/env bash
# The scripted lead (D91, proposal P2): runs a mission's loop without an LLM
# lead. It does what .pi/prompts/factory.md tells the lead to do, step by step,
# and decides nothing a script does not: next.sh picks the step, workflow.sh
# writes the wave, the runner runs it, integrate/collect/record-no-patch/human
# record the outcome. It stops where the lead stops: at a human step, a
# provider error, a script failure, or a step it does not know.
#
# Usage: scripts/factory/run.sh <feature> [--no-preflight] [--max-steps N]
#
# Runner (how a workflow file is run), FACTORY_RUNNER:
#   pi-json  (default) pi -p --mode json --approve, with the driver extension
#            as the "model" (scripts/factory/driver.mjs): one subagent call,
#            no LLM. --approve trusts the project's own .pi files for the run:
#            without it the factory guard does not load (P2, spike results).
#            FACTORY_PI_BIN: the pi executable (a path, spaces allowed);
#            FACTORY_PI_CMD: a command line split on spaces (default: pi).
#   fake     $FACTORY_FAKE_RUNNER <workflow-file> prints the workflow's return
#            value as JSON (tests).
#
# Exit: 0 stopped at a human step (the NEXT line says what to do)
#       3 paused on a provider error or hang (not a round; run again later)
#
# FACTORY_RUN_IDLE_SECONDS (environment or .factory/commands.env, default 600,
# 0 off): a wave in which no run has written anything for that long is stopped
# as a provider hang (D151).
#       2 a script or the runner failed, or an unknown step: read the output
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

feature="${1:?usage: run.sh <feature> [--no-preflight] [--max-steps N]}"; shift
preflight=1; max_steps=60
while [ $# -gt 0 ]; do case "$1" in
  --no-preflight) preflight=0 ;;
  --max-steps) max_steps="${2:?}"; shift ;;
  *) die "unknown option: $1" ;;
esac; shift; done
[ -d "$(mission_dir "$feature")" ] || die "no mission '$feature'"
runner="${FACTORY_RUNNER:-pi-json}"
# Raw runner output (agent text, gateway errors, model ids) never goes in the
# mission folder, which checkpoint.sh commits: it stays in the git folder all
# worktrees share, next to the draft patches (D73).
logs="$(dirname "$(dirname "$(dirname "$(draft_patch "$feature" x)")")")/runs/$feature"; mkdir -p "$logs"   # <git-common-dir>/pi-factory/runs/<feature>
read -r -a pi_cmd <<<"${FACTORY_PI_CMD:-pi}"
[ -z "${FACTORY_PI_BIN:-}" ] || pi_cmd=("$FACTORY_PI_BIN")    # one path, spaces kept

say()  { printf 'run: %s\n' "$*"; }
# Every stop archives the runs so far (D103): pi-subagents keeps them in temp
# folders a reboot or a cleaner can empty before anyone runs archive.sh.
stop() {
  local code="$1"; shift
  [ "$runner" = fake ] || bash "$here/archive.sh" collect "$feature" >/dev/null 2>&1 || true
  printf 'run: STOP — %s\n' "$*"; exit "$code"
}

# --- running one workflow file -----------------------------------------------
# run_workflow <file>: prints the workflow's return value as JSON; non-zero
# exit with the error text on stdout when the workflow (or the runner) failed.
run_workflow() {
  local wf="$1" raw
  case "$runner" in
    fake)
      [ -n "${FACTORY_FAKE_RUNNER:-}" ] || die "FACTORY_RUNNER=fake needs FACTORY_FAKE_RUNNER"
      "$FACTORY_FAKE_RUNNER" "$wf" ;;
    pi-json)
      raw="$logs/$(basename "$wf" .js).jsonl"; rm -f "$raw.hang"
      # stdin closed: pi -p waits on an open stdin. Its own process group
      # (set -m), so a hang stops pi and every run it started (B12).
      local pid wpid t0; t0="$(node -e 'console.log(Date.now() - 1000)')"; set -m
      FACTORY_DRIVE_WORKFLOW="$wf" "${pi_cmd[@]}" -p --mode json --no-session --approve \
        -e "$here/driver.mjs" --model factory-driver/script "run the workflow" </dev/null >"$raw" 2>"$raw.err" &
      pid=$!; set +m
      idle_watch "$pid" "$raw" "$t0" >/dev/null 2>&1 & wpid=$!
      wait "$pid" || true
      kill "$wpid" 2>/dev/null || true; wait "$wpid" 2>/dev/null || true
      if [ -s "$raw.hang" ]; then cat "$raw.hang"; return 1; fi
      node -e '
        const fs = require("fs"); const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean);
        let end = null;
        for (const l of lines) { try { const e = JSON.parse(l); if (e.type === "tool_execution_end" && e.toolName === "subagent") end = e; } catch {} }
        if (!end) { const err = fs.existsSync(process.argv[1] + ".err") ? fs.readFileSync(process.argv[1] + ".err", "utf8").trim().split("\n").slice(-5).join("\n") : "";
          console.log("the runner never called the workflow" + (err ? ":\n" + err : "")); process.exit(1); }
        const text = (end.result?.content || []).map((c) => c.text || "").join("\n");
        if (end.isError || !end.result?.details?.workflow) { console.log(text || "workflow failed"); process.exit(1); }
        console.log(JSON.stringify(end.result.details.workflow.value ?? null));' "$raw" ;;
    *) die "unknown FACTORY_RUNNER: $runner (pi-json or fake)" ;;
  esac
}

# idle_watch <pid> <runner log> <wave start, ms> (D151, B12): a model call that never returns
# leaves no error, only silence; the workflow's own limit is 2 hours. When
# neither the runner's log nor any run's transcript (where archive.sh finds
# runs, FACTORY_USAGE_DIRS) has changed for FACTORY_RUN_IDLE_SECONDS (default
# 600; 0: off), the runner's process group is stopped and <log>.hang says why.
# A wave's runs in parallel share one clock: a hung worker is stopped once the
# others are done and the limit has passed with no event.
idle_watch() {
  local pid="$1" raw="$2" start="$3" limit="$idle_limit" poll now last at roots
  [ "$limit" -gt 0 ] 2>/dev/null || return 0
  poll=30; [ "$limit" -ge 120 ] || poll=1
  read -r -a roots <<<"${FACTORY_USAGE_DIRS:-.pi/subagents $HOME/.pi/agent ${TMPDIR:-/tmp}}"
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$poll"
    read -r last at < <(node "$here/idle.mjs" "$start" "$raw" "${roots[@]}")
    [ -n "$last" ] || continue
    now="$(node -e 'console.log(Date.now())')"
    [ $(((now - last) / 1000)) -ge "$limit" ] || continue
    printf 'provider hang: no event from any run for %ss (last event %s in %s); the wave was stopped\n' "$limit" \
      "$(node -e 'console.log(new Date(Number(process.argv[1])).toISOString().replace(/\.\d+Z$/, "Z"))' "$last")" \
      "$([ "$at" = - ] && echo "no run: none started" || basename "$at")" > "$raw.hang"
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    sleep 2; kill -KILL -- "-$pid" 2>/dev/null || true
    return 0
  done
}
# FACTORY_RUN_IDLE_SECONDS: environment first, then .factory/commands.env, else 600.
idle_limit="${FACTORY_RUN_IDLE_SECONDS:-}"
if [ -z "$idle_limit" ] && [ -f .factory/commands.env ]; then
  idle_limit="$(sed -n 's/^[[:space:]]*\(export[[:space:]]*\)\{0,1\}FACTORY_RUN_IDLE_SECONDS=["'"'"']\{0,1\}\([0-9][0-9]*\).*/\2/p' .factory/commands.env | tail -1)"
fi
idle_limit="${idle_limit:-600}"

# failed <wave>: a wave that failed. A provider error or hang pauses the
# mission (no round, exit 3, D58); anything else stops for a person (exit 2).
failed() {
  local line; line="$(provider_error_line "$RESULT")"
  if [ -n "$line" ]; then
    bash "$here/pause.sh" "$feature" "provider error in the $1 wave, no round recorded: $line" >/dev/null
    stop 3 "provider error in the $1 wave, mission paused (no round): $line"
  fi
  stop 2 "the $1 wave failed: $RESULT"
}

# wave <workflow.sh args...>: generates the wave, runs it; result in $RESULT.
wave() {
  local out wf
  out="$(bash "$here/workflow.sh" "$@")" || stop 2 "workflow.sh $* failed: $out"
  wf="$(sed -n 's/^WORKFLOW_FILE: //p' <<<"$out")"
  [ -n "$wf" ] || stop 2 "workflow.sh $* printed no WORKFLOW_FILE"
  WAVE_FILE="$wf"
  say "wave $1: $wf ($runner)"
  local sp=""; if [ -t 2 ]; then spin "$1" & sp=$!; fi
  if RESULT="$(run_workflow "$wf")"; then WAVE_OK=1; else WAVE_OK=0; fi
  [ -z "$sp" ] || { kill "$sp" 2>/dev/null; wait "$sp" 2>/dev/null || true; printf '\r\033[K' >&2; }
  printf '%s\n' "$RESULT" > "$logs/$(basename "$wf" .js).result.json"
}
# spin <wave>: a wave runs for minutes with no output; on a terminal only,
# show that it is alive and for how long (stderr: RESULT captures stdout).
spin() {
  local start=$SECONDS i=0 c='|/-\'
  while :; do
    printf '\r%s wave %s running %dm%02ds ' "${c:i++%4:1}" "$1" $(((SECONDS - start) / 60)) $(((SECONDS - start) % 60)) >&2
    sleep 1
  done
}

must() { # must <name> <args...>: a factory script that must succeed
  local out; out="$(bash "$here/$1" "${@:2}" 2>&1)" || stop 2 "$1 ${*:2} failed:
$out"
  [ -z "$out" ] || printf '%s\n' "$out"
}


# --- one build wave: what the lead does per ticket ----------------------------
# Sets ASKED=1 when a worker's question waits for a human. Runs under set -e:
# every step that may fail on purpose says so.
build() {
  ASKED=0
  wave build-wave "$feature"
  local tickets t patch ok out q line rows
  tickets="$(node -e '
    const s = require("fs").readFileSync(process.argv[1], "utf8"); const m = s.match(/const ITEMS = (\[[\s\S]*?\n\]);/);
    if (!m) process.exit(1);
    for (const it of JSON.parse(m[1])) console.log(it.key);' "$WAVE_FILE")" || stop 2 "cannot read the tickets of $WAVE_FILE"
  [ -n "$tickets" ] || stop 2 "no ticket in $WAVE_FILE"
  if [ "$WAVE_OK" = 0 ]; then
    line="$(provider_error_line "$RESULT")"
    if [ -n "$line" ]; then
      # A hang stops the wave after the other workers are done: their patches
      # are on disk and integrate; the rest wait for the provider (B12).
      for t in $tickets; do
        patch=""; [[ "$line" != "provider hang"* ]] || patch="$(bash "$here/locate-patch.sh" "$feature" "$t" 2>/dev/null)" || patch=""
        if [ -n "$patch" ]; then bash "$here/integrate.sh" "$feature" "$t" "$patch" || say "$t: integration failed, recorded as a round"
        else must record-no-patch.sh "$feature" "$t" --provider "$line"; fi
      done
      stop 3 "provider error, mission paused (no round): $line"
    fi
    if grep -qi 'timed out' <<<"$RESULT"; then
      say "wave timed out: salvaging the workers' worktrees"
      for t in $tickets; do bash "$here/integrate.sh" "$feature" "$t" null || say "$t: salvage failed, recorded as a round"; done
      return 0
    fi
    stop 2 "the build wave failed: $RESULT"
  fi
  # One row per ticket: ticket, patch, ok, then its output and error as base64.
  rows="$(node -e '
    let res; try { res = JSON.parse(process.argv[1]); } catch { process.exit(1); }
    if (!Array.isArray(res)) process.exit(1);
    for (const t of process.argv.slice(2)) {
      const r = res.find((x) => x && x.ticket === t) || {};
      const text = String(r.output || "") + "\n" + String(r.error || "");
      console.log([t, r.patch || "-", r.ok === false ? "no" : "yes", Buffer.from(text).toString("base64")].join(" "));
    }' "$RESULT" $tickets)" || stop 2 "cannot read the build wave's result: $RESULT"
  while read -r t patch ok out; do
    [ "$patch" != - ] || patch=""
    out="$(printf '%s' "$out" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(Buffer.from(s,"base64").toString()))')"
    if [ "$ok" = no ]; then
      line="$(provider_error_line "$out")"
      if [ -n "$line" ]; then
        must record-no-patch.sh "$feature" "$t" --provider "$line"
        stop 3 "provider error on $t, mission paused (no round): $line"
      fi
    fi
    if grep -q 'DECISION NEEDED:' <<<"$out"; then
      q="$(sed -n 's/.*DECISION NEEDED: *//p' <<<"$out" | head -1)"
      printf '%s\n' "$q" | bash "$here/human.sh" ask "$feature" "$t" --stdin > "$logs/ask-$t.log" 2>&1 \
        || stop 2 "human.sh ask failed for $t: $(cat "$logs/ask-$t.log")"
      cat "$logs/ask-$t.log"
      if grep -q 'AUTO-ANSWERED' "$logs/ask-$t.log"; then :
      elif grep -q '^HELD' "$logs/ask-$t.log"; then :      # D142: only that ticket waits
      elif grep -q 'ASKED' "$logs/ask-$t.log"; then ASKED=1
      else stop 2 "human.sh ask for $t said neither ASKED, HELD nor AUTO-ANSWERED"; fi
      continue
    fi
    [ -n "$patch" ] || patch="$(bash "$here/locate-patch.sh" "$feature" "$t" 2>/dev/null)" || patch=""
    if [ -n "$patch" ]; then
      bash "$here/integrate.sh" "$feature" "$t" "$patch" || say "$t: integration failed, recorded as a round"
    else
      must record-no-patch.sh "$feature" "$t"
    fi
  done <<<"$rows"
}

# --- the loop -----------------------------------------------------------------
if [ "$preflight" = 1 ]; then must doctor.sh --quick "$feature"; fi
steps=0; last=""
while :; do
  steps=$((steps + 1))
  [ "$steps" -le "$max_steps" ] || stop 2 "more than $max_steps steps: check the mission (next.sh $feature)"
  nxt="$(bash "$here/next.sh" "$feature")" || stop 2 "next.sh failed: $nxt"
  step="$(sed -n '1s/^STEP: //p' <<<"$nxt")"
  # Watchdog: the same state twice in a row means the last action changed nothing.
  [ "$nxt" != "$last" ] || stop 2 "no progress at STEP: $step (the last action changed nothing)
$nxt"
  last="$nxt"
  say "step $steps: $step"
  case "$step" in
    paused)
      if [ "$steps" = 1 ]; then must pause.sh resume "$feature"; continue; fi
      printf '%s\n' "$nxt"; stop 3 "the mission paused itself" ;;
    install)
      must install.sh "$feature" ;;
    context-sync)
      must context.sh sync "$feature" ;;
    investigate)
      wave investigate "$feature"; [ "$WAVE_OK" = 1 ] || failed investigate ;;
    contract|design|validate|steward)
      wave "$step" "$feature"; [ "$WAVE_OK" = 1 ] || failed "$step"
      case "$step" in contract|design) ;; *) must collect.sh "$feature" ;; esac ;;
    behavior-stale)
      wave validate "$feature"; [ "$WAVE_OK" = 1 ] || failed validate
      must collect.sh "$feature" ;;
    tickets|behavior-fix|health-fix)
      task=all; [ "$step" = behavior-fix ] && task=fix-behavior; [ "$step" = health-fix ] && task=fix-health
      wave tickets "$feature" "$task"; [ "$WAVE_OK" = 1 ] || failed tickets ;;
    health)
      bash "$here/health.sh" check "$feature" || say "health check failed (recorded; the loop continues)" ;;
    verify)
      bash "$here/verify.sh" "$feature" || say "done condition failed (recorded; the loop continues)" ;;
    build)
      build
      if [ "$ASKED" = 1 ]; then
        printf '%s\n' "$(bash "$here/next.sh" "$feature")"; echo "WAITING: human (a worker asked a question)"; exit 0
      fi ;;
    review)
      wave review-wave "$feature"; [ "$WAVE_OK" = 1 ] || failed review
      must collect.sh "$feature" ;;
    pr)
      must metrics.sh "$feature"
      printf '%s\n' "$nxt"; echo "WAITING: human (pr)"; exit 0 ;;
    pr-draft)
      must metrics.sh "$feature"; must mr.sh "$feature" --draft ;;
    mr-open|closed)
      printf '%s\n' "$nxt"; exit 0 ;;
    *)
      printf '%s\n' "$nxt"
      if [[ "$HUMAN_STEPS" == *" $step "* ]]; then echo "WAITING: human ($step)"; exit 0; fi
      stop 2 "unknown step '$step'" ;;
  esac
done
