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
#       3 paused on a provider error (not a round; run again later)
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
stop() { local code="$1"; shift; printf 'run: STOP — %s\n' "$*"; exit "$code"; }

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
      raw="$logs/$(basename "$wf" .js).jsonl"
      # stdin closed: pi -p waits on an open stdin.
      FACTORY_DRIVE_WORKFLOW="$wf" "${pi_cmd[@]}" -p --mode json --no-session --approve \
        -e "$here/driver.mjs" --model factory-driver/script "run the workflow" </dev/null >"$raw" 2>"$raw.err" || true
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

# wave <workflow.sh args...>: generates the wave, runs it; result in $RESULT.
wave() {
  local out wf
  out="$(bash "$here/workflow.sh" "$@")" || stop 2 "workflow.sh $* failed: $out"
  wf="$(sed -n 's/^WORKFLOW_FILE: //p' <<<"$out")"
  [ -n "$wf" ] || stop 2 "workflow.sh $* printed no WORKFLOW_FILE"
  WAVE_FILE="$wf"
  say "wave $1: $wf ($runner)"
  if RESULT="$(run_workflow "$wf")"; then WAVE_OK=1; else WAVE_OK=0; fi
  printf '%s\n' "$RESULT" > "$logs/$(basename "$wf" .js).result.json"
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
      for t in $tickets; do must record-no-patch.sh "$feature" "$t" --provider "$line"; done
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
      elif grep -q 'ASKED' "$logs/ask-$t.log"; then ASKED=1
      else stop 2 "human.sh ask for $t said neither ASKED nor AUTO-ANSWERED"; fi
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
    grill|approve|approve-design|decide|approve-tickets|coverage|setup|escalate|blocked|unverified|approve-conclusion|handoff|report)
      printf '%s\n' "$nxt"; echo "WAITING: human ($step)"; exit 0 ;;
    context-sync)
      must context.sh sync "$feature" ;;
    investigate)
      wave investigate "$feature"; [ "$WAVE_OK" = 1 ] || stop 2 "the investigate wave failed: $RESULT" ;;
    contract|design|validate|steward)
      wave "$step" "$feature"; [ "$WAVE_OK" = 1 ] || stop 2 "the $step wave failed: $RESULT"
      case "$step" in contract|design) ;; *) must collect.sh "$feature" ;; esac ;;
    behavior-stale)
      wave validate "$feature"; [ "$WAVE_OK" = 1 ] || stop 2 "the validate wave failed: $RESULT"
      must collect.sh "$feature" ;;
    tickets|behavior-fix|health-fix)
      task=all; [ "$step" = behavior-fix ] && task=fix-behavior; [ "$step" = health-fix ] && task=fix-health
      wave tickets "$feature" "$task"; [ "$WAVE_OK" = 1 ] || stop 2 "the tickets wave failed: $RESULT" ;;
    health)
      bash "$here/health.sh" check "$feature" || say "health check failed (recorded; the loop continues)" ;;
    build)
      build
      if [ "$ASKED" = 1 ]; then
        printf '%s\n' "$(bash "$here/next.sh" "$feature")"; echo "WAITING: human (a worker asked a question)"; exit 0
      fi ;;
    review)
      wave review-wave "$feature"; [ "$WAVE_OK" = 1 ] || stop 2 "the review wave failed: $RESULT"
      must collect.sh "$feature" ;;
    pr)
      must metrics.sh "$feature"
      printf '%s\n' "$nxt"; echo "WAITING: human (pr)"; exit 0 ;;
    *) printf '%s\n' "$nxt"; stop 2 "unknown step '$step'" ;;
  esac
done
