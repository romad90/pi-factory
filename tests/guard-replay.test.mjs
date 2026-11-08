// Replay of real refusals (learning loop): each call in fixtures/guard-replay.json
// was refused by the guard during a real mission and cost a round, a detour or
// a human decision (ids are rows of that mission's cause taxonomy). Each must
// now pass in the context it ran in. The second test holds the line: what
// those fixes must not let through.
// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { check } from "../scripts/factory/guard-rules.mjs";

const main = mkdtempSync(join(tmpdir(), "replay-main-"));
mkdirSync(join(main, ".git"));
const workerGit = mkdtempSync(join(tmpdir(), "replay-gitdir-"));
writeFileSync(join(workerGit, "HEAD"), "ref: refs/heads/pi-subagents/01-x-abc123-s0-t0\n");
const worker = mkdtempSync(join(tmpdir(), "replay-worker-"));
writeFileSync(join(worker, ".git"), `gitdir: ${workerGit}\n`);
const cwdOf = { lead: main, judge: main, worker };
const fill = (v) => (typeof v === "string" ? v.replaceAll("{root}", main)
  : Array.isArray(v) ? v.map(fill)
  : v && typeof v === "object" ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, fill(x)])) : v);

const cases = JSON.parse(readFileSync(new URL("./fixtures/guard-replay.json", import.meta.url), "utf8"));

test("replay: every refusal recorded in a real mission now passes where it ran", () => {
  for (const c of cases) {
    const out = check({ tool: c.tool, input: fill(c.input), cwd: cwdOf[c.context] });
    assert.equal(out, null, `${c.id} (${c.context}, ${c.tool}) still refused: ${out?.reason}`);
  }
});

test("replay: the fixes let nothing dangerous through", () => {
  const bash = (command, cwd = main) => check({ tool: "bash", input: { command }, cwd });
  const sub = (input, cwd = main) => check({ tool: "subagent", input, cwd });
  // A heredoc fed to a shell is shell, not data.
  for (const cmd of [
    "bash <<'EOF'\nrm -rf .scratch/m\nEOF",
    "sh <<EOF\necho x > notes.md\nEOF",
    "zsh -s <<'X'\nrm .scratch/m/spec.md\nX",
  ]) assert.ok(bash(cmd), `should block: ${JSON.stringify(cmd)}`);
  // Mission records: only the mission's tmp/ is a worker's to delete.
  for (const cmd of [
    "rm -f .scratch/m/spec.md", "rm .scratch/m/tmp/a.txt .scratch/m/verdicts/01-code.md",
    "rm .scratch/m/tmp/../spec.md", "rm -rf .scratch/m/tmp/../../.scratch", "rm -rf .scratch/m",
  ]) assert.ok(bash(cmd, worker), `should block in a worker: ${cmd}`);
  // Shared dependencies, on one line or several.
  for (const cmd of [
    "cp x.js node_modules/tap/index.js", "sed -i '' s/a/b/ node_modules/x/index.js",
    "echo ok\nrm -rf node_modules/tap", "printf x > node_modules/a.js",
  ]) assert.ok(bash(cmd, worker), `should block in a worker: ${JSON.stringify(cmd)}`);
  // Subagent launches: only a generated workflow, fresh and blocking; only the
  // review axis directly, fresh, in this project; only read-only actions.
  const wf = "./.scratch/m/workflows/20261108-000000-build-wave.js";
  for (const input of [
    { workflow: wf, async: true, options: { context: "fresh" } },
    { workflow: wf, async: false, options: { context: "fork" } },
    { agent: "factory-review-axis", task: "x", options: { context: "fresh" }, cwd: "/etc" },
    { agent: "factory-review-axis", task: "x", options: { context: "fork" }, cwd: main },
    { agent: "factory-review-axis", task: "x", cwd: main, model: "x/y" },
    { agent: "factory-worker", task: "x", options: { context: "fresh" }, cwd: main },
    { action: "steer", id: "abc", message: "do it this way" },
    { action: "resume", id: "abc", message: "go on" },
  ]) assert.ok(sub(input), `should block: ${JSON.stringify(input)}`);
  for (const input of [
    { action: "status", id: "abc" }, { action: "list" }, { action: "get", id: "abc" },
    { workflow: wf, async: false, context: "fresh" },
  ]) assert.equal(sub(input), null, `should allow: ${JSON.stringify(input)}`);
});
