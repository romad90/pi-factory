#!/usr/bin/env bash
# Generates the exact workflow script for the next wave of a mission (D33)
# and writes it to a file. The lead passes only the printed path:
#   subagent({ workflow: "<path>", context: "fresh", async: false })
# Nothing is retyped by the lead, and the file stays as an audit record of
# what actually ran. All data (who runs, with which brief) comes from the
# mission's files, so the lead relays orchestration instead of improvising it.
#
# Usage:
#   scripts/factory/workflow.sh contract    <feature>
#   scripts/factory/workflow.sh tickets     <feature> <all|fix-behavior|fix-health>
#   scripts/factory/workflow.sh build-wave  <feature>
#   scripts/factory/workflow.sh review-wave <feature>
#   scripts/factory/workflow.sh validate    <feature>
#   scripts/factory/workflow.sh steward     <feature>
#   scripts/factory/workflow.sh light       <slug> <base-ref>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

mode="${1:?usage: workflow.sh <contract|design|tickets|build-wave|review-wave|validate|steward|light> <feature> ...}"
feature="${2:?usage: workflow.sh <mode> <feature> ...}"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
items="$tmp/items.tsv"; : > "$items"

add() {                     # <key> <agent> <worktree:true|false> <brief args...>
  local key="$1" agent="$2" wt="$3"; shift 3
  bash "$here/brief.sh" "$@" > "$tmp/$key.brief"
  printf '%s\t%s\t%s\t%s\n' "$key" "$agent" "$wt" "$tmp/$key.brief" >> "$items"
}

json_args() {               # items.tsv → JSON array (node, else python3)
  if command -v node >/dev/null; then
    node -e '
      const fs = require("fs");
      const rows = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean);
      const out = rows.map(r => { const [key, agent, wt, f] = r.split("\t");
        return { key, agent, worktree: wt === "true", task: fs.readFileSync(f, "utf8") }; });
      process.stdout.write(JSON.stringify(out, null, 2));' "$items"
  else
    python3 -c '
import json, sys
out = []
for r in open(sys.argv[1]).read().splitlines():
    if not r: continue
    key, agent, wt, f = r.split("\t")
    out.append({"key": key, "agent": agent, "worktree": wt == "true", "task": open(f).read()})
print(json.dumps(out, indent=2), end="")' "$items"
  fi
}

case "$mode" in
  contract)
    # Amendment requests (human.sh amend) go to this wave, then are marked sent.
    shopt -s nullglob
    for a in "$(mission_dir "$feature")"/amendments/*.md; do
      grep -q '^\*\*Status:\*\* pending' "$a" && sed -i.bak "s/^\*\*Status:\*\* pending.*/**Status:** sent $(date +%F)/" "$a" && rm -f "$a.bak"
    done
    add contract-author factory-contract-author false contract-author "$feature"
    add contract-critic factory-contract-critic false contract-critic "$feature"
    body='const out = [];
for (const it of ITEMS) {            // sequential: the critic reads the author'"'"'s result
  const r = await runs.run(it.key, { agent: it.agent, task: it.task });
  out.push({ key: it.key, output: r.output });
}
return out;'
    ;;

  design)
    # D94: the program design, after G1 and before tickets; a human approves it.
    contract_approved "$(mission_dir "$feature")/spec.md" || die "approve the contract first (G1)"
    add designer factory-designer false designer "$feature"
    body='const it = ITEMS[0];
const r = await runs.run(it.key, { agent: it.agent, task: it.task });
return { output: r.output };'
    ;;

  tickets)
    # D52: tickets (or fix tickets from a verdict's findings) by a fresh agent;
    # a human approves them (/factory-approve <feature> tickets) before any build.
    task="${3:?usage: workflow.sh tickets <feature> <all|fix-behavior|fix-health>}"
    d="$(mission_dir "$feature")"; mkdir -p "$d/state" "$d/issues"
    printf '**Task:** %s\n**Requested:** %s\n' "$task" "$(date +%F)" > "$d/state/tickets.pending"
    bash "$here/checkpoint.sh" "$feature" >/dev/null
    add ticket-writer factory-ticket-writer false ticket-writer "$feature" "$task"
    body='const it = ITEMS[0];
const r = await runs.run(it.key, { agent: it.agent, task: it.task });
return { output: r.output };'
    ;;

  steward)
    # D49: the code steward judges the whole mission diff against the quality
    # bar, with the deterministic health report (health.sh check) as evidence.
    d="$(mission_dir "$feature")"
    code_verdict_is_fresh "$(verdict_field "$d/health/report.md" Commit)" \
      || die "no health report for HEAD: run scripts/factory/health.sh check $feature first"
    add code-steward factory-code-steward false code-steward "$feature" - "$(git rev-parse HEAD)" "$(mission_base "$feature")"
    body='const it = ITEMS[0];
const r = await runs.run(it.key, { agent: it.agent, task: it.task });
return { output: r.output };'
    ;;

  build-wave)
    # Worktrees branch from HEAD, so mission state must be committed (D46).
    bash "$here/checkpoint.sh" "$feature" >/dev/null
    compute_ticket_state "$feature"
    [ ${#T_BUILD[@]} -gt 0 ] || die "nothing to build for $feature (run next.sh)"
    n=0
    for name in "${T_BUILD[@]}"; do
      [ "$n" -ge "$FACTORY_MAX_PARALLEL" ] && break
      agent=factory-worker
      [ "${T_ROUND[$name]:-0}" -ge 2 ] && agent=factory-worker-heavy      # D24 escalation
      # D52: an L ticket goes straight to the heavy worker.
      grep -qE '^\*\*Size:\*\* *L\b' "$(mission_dir "$feature")/issues/$name.md" && agent=factory-worker-heavy
      add "$name" "$agent" true worker "$feature" "$name"
      n=$((n + 1))
    done
    # D78: with FACTORY_SELF_CHECK_GATE=1 (commands.env), pi-subagents runs the
    # self-check in each worker's worktree when it finishes (a per-child gate);
    # a red hand-over goes back to the same session once, with the failure.
    load_commands
    gate=null
    if [ "${FACTORY_SELF_CHECK_GATE:-0}" = 1 ]; then
      prefix="$(project_prefix)"
      qp="$(printf %q "$prefix")"; qf="$(printf %q "$feature")"
      gate="$(node -e 'process.stdout.write(JSON.stringify({ command: process.argv[1], timeoutMs: 600000 }))' \
        "${prefix:+cd $qp && }bash scripts/factory/self-check.sh $qf")"
    fi
    # A new round starts without the last round's self-check result (D78).
    for name in "${T_BUILD[@]}"; do rm -f "$(draft_patch "$feature" "$name").status"; done
    body='const GATE = '"$gate"';
const first = await runs.all(ITEMS.map(it => Object.assign({
  key: it.key, agent: it.agent, task: it.task, worktree: true,
}, GATE ? { gate: GATE } : {})));
const results = [];
for (let i = 0; i < first.length; i++) {
  let r = first[i];
  // Only a red self-check goes back; a stop for a human decision, or a
  // provider error, is returned as it is.
  const gateFailed = GATE && r && r.ok === false && /SELF-CHECK: FAIL/.test(String(r.error || "")) &&
    !/No change against HEAD/.test(String(r.error || "")) && !/DECISION NEEDED/.test(String(r.output || ""));
  if (gateFailed && r.resumability && r.resumability.state === "resumable") {
    r = await runs.run(ITEMS[i].key + "-selfcheck", { resume: r.runId, task:
      "Your hand-over failed the self-check:\n" + String(r.error || "") +
      "\nFix the code, run " + GATE.command + " until it prints SELF-CHECK: PASS, then report again." });
  }
  results.push(r);
}
// D39: return the patch path, so the lead never searches for it.
const patchOf = (r) => {
  const paths = [].concat(r?.artifactPaths ?? [], r?.handoff?.artifactPaths ?? []);
  return paths.find((p) => /\.(patch|diff)$/.test(p)) ?? r?.patchPath ?? r?.handoff?.patchPath ?? null;
};
return results.map((r, i) => ({
  ticket: ITEMS[i].key, patch: patchOf(r), output: r?.output,
  artifactPaths: r?.artifactPaths, handoff: r?.handoffPath ?? r?.handoff ?? null,
  ok: r?.ok, error: r?.error ?? null, usage: r?.results?.[0]?.usage ?? null,
}));'
    ;;

  review-wave)
    compute_ticket_state "$feature"
    [ ${#T_REVIEW[@]} -gt 0 ] || die "nothing to review for $feature (run next.sh)"
    for name in "${T_REVIEW[@]}"; do
      add "$name" factory-reviewer false reviewer "$feature" "$name" "$(ticket_marker "$feature" "$name")"
    done
    body='const results = await runs.all(ITEMS.map(it => ({
  key: it.key, agent: it.agent, task: it.task,
})));
return results.map((r, i) => ({ ticket: ITEMS[i].key, output: r.output }));'
    ;;

  validate)
    add behavior factory-validator false validator "$feature" - "$(git rev-parse HEAD)"
    body='const it = ITEMS[0];
const r = await runs.run(it.key, { agent: it.agent, task: it.task });
return { output: r.output };'
    ;;

  light)
    base="${3:?usage: workflow.sh light <slug> <base-ref>}"
    add light factory-reviewer false light-reviewer "$feature" - "$(git rev-parse HEAD)" "$(git rev-parse "$base")"
    body='const it = ITEMS[0];
const r = await runs.run(it.key, { agent: it.agent, task: it.task });
return { output: r.output };'
    ;;

  *) die "unknown mode: $mode" ;;
esac

if [ "$mode" = "light" ]; then wf_dir="$FACTORY_DIR/light/$feature/workflows"
else wf_dir="$(mission_dir "$feature")/workflows"; fi
mkdir -p "$wf_dir"
wf_file="$wf_dir/$(date +%Y%m%d-%H%M%S)-$mode.js"
i=2; while [ -e "$wf_file" ]; do wf_file="$wf_dir/$(date +%Y%m%d-%H%M%S)-$mode-$i.js"; i=$((i + 1)); done
{
  printf '// Generated by scripts/factory/workflow.sh %s %s. Do not edit.\n' "$mode" "$feature"
  printf 'const ITEMS = %s;\n' "$(json_args)"
  printf '%s\n' "$body"
} > "$wf_file"

# D77: who ran with which model, as configured when the wave was generated
# (models change mid-mission). metrics.sh reads it; nothing else depends on it.
runs_tsv="$(dirname "$wf_dir")/runs.tsv"
[ -f "$runs_tsv" ] || printf 'date\tworkflow\tkey\tagent\tmodel\tthinking\n' > "$runs_tsv"
effective="$(node "$here/effective-models.mjs" 2>/dev/null || true)"     # D92: overrides included
while IFS=$'\t' read -r key agent _ _; do
  mt="$(printf '%s\n' "$effective" | awk -F'\t' -v n="$agent" '$1 == n { print $2 "\t" $3; exit }')"
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date '+%F %H:%M')" "$(basename "$wf_file")" "$key" "$agent" "${mt:-$'\t'}" >> "$runs_tsv"
done < "$items"
# The files are written after the checkpoints above, so commit them now. An
# untracked file makes the tree dirty and worktree admission refuses to run.
if [ "$mode" = "light" ]; then bash "$here/checkpoint.sh" --light "$feature" >/dev/null
else bash "$here/checkpoint.sh" "$feature" >/dev/null; fi

echo "WORKFLOW_FILE: ./$wf_file"
echo "Pass it as: subagent({ workflow: \"./$wf_file\", context: \"fresh\", async: false })"
