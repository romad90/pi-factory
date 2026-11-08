// The run page (D121): "why did ticket 03 fail?" answered from the archive:
// the refused command, its rule, whether today's guard still refuses it, and
// the run call by call.
// Run: node --test tests/run-detail.test.mjs
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { events, replay, runDetail } from "../scripts/factory/run-detail.mjs";

// Under the home folder, like a real project (see guard-replay.test.mjs).
const project = mkdtempSync(join(homedir(), ".factory-run-detail-"));
after(() => rmSync(project, { recursive: true, force: true }));
mkdirSync(join(project, ".git")); mkdirSync(join(project, ".factory"));
// E39, as the reviewer of ticket 03 sent it: $PWD read as outside the project.
const e39 = { command: 'mkdir -p .scratch/m/tmp/review-03; export TMPDIR="$PWD/.scratch/m/tmp/review-03"; npm test > "$TMPDIR/npm-test.log" 2>&1' };
const line = (o) => JSON.stringify(o);

test("replay: a refusal fixed since says allowed today; one that must stay refused says so; a cut input can't be replayed", () => {
  assert.equal(replay({ tool: "bash", input: line(e39), cwd: project }).today, "allowed");
  const push = replay({ tool: "bash", input: line({ command: "git push --force" }), cwd: project });
  assert.equal(push.today, "refused"); assert.ok(push.rule);
  assert.equal(replay({ tool: "bash", input: line(e39).slice(0, 60), cwd: project }).today, "unknown");
});

test("events: calls with their result, failures and refusals in place, the agent's text", () => {
  const t = [
    line({ recordType: "tool_start", toolCallId: "a", toolName: "read", argsPreview: "src/server.js", timestamp: "2026-11-08T17:48:00Z" }),
    line({ recordType: "message", role: "toolResult", toolCallId: "a", text: "module.exports = …" }),
    line({ recordType: "tool_start", toolCallId: "b", toolName: "bash", argsPreview: e39.command }),
    line({ recordType: "message", role: "toolResult", toolCallId: "b", isError: true, text: "redirect outside the project: blocked by the factory guard" }),
    line({ recordType: "tool_start", toolCallId: "c", toolName: "bash", argsPreview: "npm test" }),
    line({ recordType: "message", role: "toolResult", toolCallId: "c", text: "npm ERR! exited with code 1" }),
    line({ recordType: "message", message: { role: "assistant", content: [{ type: "text", text: "FAIL: checks unverified" }, { type: "toolCall", name: "x" }] } }),
    "not json",
  ].join("\n");
  const ev = events(t);
  assert.deepEqual(ev.map((e) => e.kind), ["call", "refused", "call", "text"]);
  assert.equal(ev[0].at, "2026-11-08T17:48:00.000Z");
  assert.equal(ev[1].error, true); assert.match(ev[1].result, /blocked by the factory guard/);
  assert.equal(ev[2].error, true);
  assert.equal(ev[3].text, "FAIL: checks unverified");
});

test("runDetail: the archived run with times, counts and each refusal judged again", () => {
  const dir = join(project, "06bd1e36_factory-reviewer"); mkdirSync(dir);
  writeFileSync(join(dir, "run.json"), JSON.stringify({
    run: "06bd1e36", agent: "factory-reviewer", model: "m", ticket: "03", date: "2026-11-08T17:49:23.000Z", durationMs: 86000,
    usage: { input: 10, output: 2, cost: 0.1 }, calls: 2, outcome: { result: "FAIL" },
    guard: [{ date: "2026-11-08T17:48:30.000Z", rule: "strayWrite", tool: "bash", input: line(e39), cwd: project }],
  }));
  writeFileSync(join(dir, "transcript.jsonl"), line({ recordType: "tool_start", toolCallId: "b", toolName: "bash", argsPreview: "npm test" }) + "\n");
  writeFileSync(join(dir, "output.md"), "FAIL");
  const d = runDetail(dir);
  assert.equal(d.role, "reviewer"); assert.equal(d.dir, "06bd1e36_factory-reviewer");
  assert.equal(d.start, "2026-11-08T17:47:57.000Z"); assert.equal(d.end, "2026-11-08T17:49:23.000Z");
  assert.equal(d.calls, 2); assert.equal(d.events.length, 1); assert.equal(d.output, "FAIL");
  assert.equal(d.refused[0].rule, "strayWrite"); assert.equal(d.refused[0].today, "allowed");
  assert.equal(runDetail(join(project, "nope")), null);
});
