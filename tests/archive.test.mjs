// The run archive's times and refusals (found on the gym's records: every
// run had durationMs 0, so the timeline drew points and no refusal was
// attached to any run).
// Run: node --test tests/archive.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { refusalsFor, toolCalls, transcriptSpan } from "../scripts/factory/archive.mjs";

const rec = (o) => JSON.stringify({ version: 1, recordType: "message", ...o });
// The reviewer of ticket 01 (8779b383), as pi-subagents writes it: ts in ms and an ISO timestamp.
const reviewer = [
  rec({ ts: Date.parse("2026-11-08T16:20:55.244Z"), timestamp: "2026-11-08T16:20:55.244Z", role: "user", text: "[prompt redacted]" }),
  JSON.stringify({ recordType: "tool_start", toolCallId: "a", toolName: "bash", argsPreview: "cd .scratch/m/tmp/review-01/commit && node_modules/.bin/tap --no-cov -R tap > ../out.txt", ts: Date.parse("2026-11-08T16:21:31.500Z") }),
  rec({ ts: Date.parse("2026-11-08T16:22:04.109Z"), role: "assistant", text: "FAIL" }),
].join("\n");
const axis = [rec({ ts: Date.parse("2026-11-08T16:20:58Z") }), JSON.stringify({ recordType: "tool_start", toolCallId: "b", toolName: "read", argsPreview: "lib/server.js" }), rec({ ts: Date.parse("2026-11-08T16:21:41Z") })].join("\n");
const refusal = (date, command) => ({ t: Date.parse(date), date, rule: "scratch", tool: "bash", input: JSON.stringify({ command }), cwd: "/p" });

test("a run's start and end come from its transcript, not the meta file's time", () => {
  assert.deepEqual(transcriptSpan(reviewer), { start: Date.parse("2026-11-08T16:20:55.244Z"), end: Date.parse("2026-11-08T16:22:04.109Z") });
  assert.equal(transcriptSpan("not json\n"), null);
  assert.equal(toolCalls(reviewer), 1);
});

test("a refusal goes to the run that made the call, not to a parallel run in the same window", () => {
  const g = [refusal("2026-11-08T16:21:31.538Z", "cd .scratch/m/tmp/review-01/commit && node_modules/.bin/tap --no-cov -R tap > ../out.txt")];
  assert.equal(refusalsFor(reviewer, Date.parse("2026-11-08T16:20:55Z"), Date.parse("2026-11-08T16:22:04Z"), g).length, 1);
  assert.equal(refusalsFor(axis, Date.parse("2026-11-08T16:20:58Z"), Date.parse("2026-11-08T16:21:41Z"), g).length, 0);
  assert.equal(refusalsFor(reviewer, Date.parse("2026-11-08T16:30:00Z"), Date.parse("2026-11-08T16:31:00Z"), g).length, 0, "outside the window");
});

test("an input cut at 300 characters in guard.log is still matched by its first characters", () => {
  const long = "cd .scratch/m/tmp/review-01/commit && node_modules/.bin/tap --no-cov -R tap > ../out.txt " + "x".repeat(400);
  const cut = { ...refusal("2026-11-08T16:21:31.538Z", ""), input: JSON.stringify({ command: long }).slice(0, 300) };
  assert.equal(refusalsFor(reviewer, Date.parse("2026-11-08T16:20:55Z"), Date.parse("2026-11-08T16:22:04Z"), [cut]).length, 1);
});
