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
#   pi-json  (default) pi -p --mode json, with the driver extension as the
#            "model" (scripts/factory/driver.mjs): one subagent call, no LLM.
#            FACTORY_PI_CMD overrides the pi command (default: pi).
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
dir="$(mission_dir "$feature")"
runner="${FACTORY_RUNNER:-pi-json}"
logs="$dir/logs"; mkdir -p "$logs"

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
      FACTORY_DRIVE_WORKFLOW="$wf" ${FACTORY_PI_CMD:-pi} -p --mode json --no-session --approve \
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

provider_error() { grep -Eio '(^|[^0-9])(429|5[0-9][0-9])([^0-9]|$).*|rate.?limit.*|quota.*|overloaded.*' <<<"$1" | head -1; }

# --- one build wave: what the lead does per ticket ----------------------------
build() {
  wave build-wave "$feature"
  local tickets asked=0 t patch ok out err line
  tickets="$(node -e '
    const s = require("fs").readFileSync(process.argv[1], "utf8"); const m = s.match(/const ITEMS = (\[[\s\S]*?\n\]);/);
    for (const it of JSON.parse(m[1])) console.log(it.key);' "$WAVE_FILE")"
  if [ "$WAVE_OK" = 0 ]; then
    if line="$(provider_error "$RESULT")" && [ -n "$line" ]; then
      for t in $tickets; do must record-no-patch.sh "$feature" "$t" --provider "$line"; done
      stop 3 "provider error, mission paused (no round): $line"
    fi
    if grep -qi 'timed out' <<<"$RESULT"; then
      say "wave timed out: salvaging the workers' worktrees"
      for t in $tickets; do bash "$here/integrate.sh" "$feature" "$t" null || true; done
      return 0
    fi
    stop 2 "the build wave failed: $RESULT"
  fi
  for t in $tickets; do
    IFS='|' read -r patch ok < <(node -e '
      const r = (JSON.parse(process.argv[1]) || []).find((x) => x && x.ticket === process.argv[2]) || {};
      console.log([r.patch || "", r.ok === false ? "no" : "yes"].join("|"));' "$RESULT" "$t")
    out="$(node -e '
      const r = (JSON.parse(process.argv[1]) || []).find((x) => x && x.ticket === process.argv[2]) || {};
      process.stdout.write(String(r.output || "") + "\n" + String(r.error || ""));' "$RESULT" "$t")"
    if [ "$ok" = no ] && line="$(provider_error "$out")" && [ -n "$line" ]; then
      must record-no-patch.sh "$feature" "$t" --provider "$line"
      stop 3 "provider error on $t, mission paused (no round): $line"
    fi
    if grep -q 'DECISION NEEDED:' <<<"$out"; then
      err="$(sed -n 's/.*DECISION NEEDED: *//p' <<<"$out" | head -1)"
      printf '%s\n' "$err" | bash "$here/human.sh" ask "$feature" "$t" --stdin | tee "$logs/ask-$t.log"
      grep -q 'AUTO-ANSWERED' "$logs/ask-$t.log" || asked=1
      continue
    fi
    if [ -z "$patch" ]; then patch="$(bash "$here/locate-patch.sh" "$feature" "$t" 2>/dev/null || true)"; fi
    if [ -n "$patch" ]; then
      bash "$here/integrate.sh" "$feature" "$t" "$patch" || say "$t: integration failed, recorded as a round"
    else
      must record-no-patch.sh "$feature" "$t"
    fi
  done
  [ "$asked" = 0 ] || return 10
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
    grill|approve|decide|approve-tickets|coverage|setup|escalate|blocked|unverified)
      printf '%s\n' "$nxt"; echo "WAITING: human ($step)"; exit 0 ;;
    contract|validate|steward)
      wave "$step" "$feature"; [ "$WAVE_OK" = 1 ] || stop 2 "the $step wave failed: $RESULT"
      [ "$step" = contract ] || must collect.sh "$feature" ;;
    behavior-stale)
      wave validate "$feature"; [ "$WAVE_OK" = 1 ] || stop 2 "the validate wave failed: $RESULT"
      must collect.sh "$feature" ;;
    tickets|behavior-fix|health-fix)
      task=all; [ "$step" = behavior-fix ] && task=fix-behavior; [ "$step" = health-fix ] && task=fix-health
      wave tickets "$feature" "$task"; [ "$WAVE_OK" = 1 ] || stop 2 "the tickets wave failed: $RESULT" ;;
    health)
      bash "$here/health.sh" check "$feature" || say "health check failed (recorded; the loop continues)" ;;
    build)
      rc=0; build || rc=$?
      if [ "$rc" = 10 ]; then
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
