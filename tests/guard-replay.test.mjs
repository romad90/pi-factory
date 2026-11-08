// Replay of real refusals (learning loop): each call in fixtures/guard-replay.json
// was refused by the guard during a real mission and cost a round, a detour or
// a human decision (ids are rows of that mission's cause taxonomy). Each must
// now pass in the context it ran in. The second test holds the line: what
// those fixes must not let through.
// Run: node --test tests/guard-replay.test.mjs. Lesson fixtures (ids L-…, D115) carry {root}, {home}
// and {tmp}, filled here.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { check } from "../scripts/factory/guard-rules.mjs";

// Not under the temp folder: a write to ../x from a project there lands in the
// temp folder, which the guard allows, and would hide what a real project sees.
const main = mkdtempSync(join(homedir(), ".factory-replay-main-"));
after(() => rmSync(main, { recursive: true, force: true }));
mkdirSync(join(main, ".git")); mkdirSync(join(main, ".factory"));   // a real project has both
const workerGit = mkdtempSync(join(tmpdir(), "replay-gitdir-"));
writeFileSync(join(workerGit, "HEAD"), "ref: refs/heads/pi-subagents/01-x-abc123-s0-t0\n");
const worker = mkdtempSync(join(tmpdir(), "replay-worker-"));
writeFileSync(join(worker, ".git"), `gitdir: ${workerGit}\n`);
const cwdOf = { lead: main, judge: main, worker };
const fill = (v) => (typeof v === "string" ? v.replaceAll("{root}", main).replaceAll("{home}", homedir()).replaceAll("{tmp}", tmpdir())
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
  // A redirect after a cd is read from where the cd went (E33), and only there:
  // a cd inside parentheses ends with them; a cd to an unknown place proves nothing.
  for (const cmd of [
    "cd .scratch/m/tmp && echo x > ../../../notes.md", "cd src && echo x > a.js",
    "(cd .scratch/m/tmp) && echo x > ../../notes.md", "(cd .scratch/m/tmp && true); echo x > ../notes.md",
    "cd \"$D\" && echo x > ../notes.md", "cd ~ && echo x > notes.md", "cd .scratch/m/tmp; cd .. ; cd ..; cd ..; echo x > notes.md",
  ]) assert.ok(bash(cmd), `should block a lead or judge write: ${JSON.stringify(cmd)}`);
  for (const cmd of ["cd .scratch/m/tmp/a && echo x > ../b.log", "cd .scratch/m && (cd tmp && echo x > y.log)", "cd /tmp && echo x > y.log"])
    assert.equal(bash(cmd), null, `should allow: ${cmd}`);
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
