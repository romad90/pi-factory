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

// abandon-timeout, archive run 47ac94a6…_factory-contract-author (paths anonymized):
// every assistant message carries usage.totalTokens, and the redaction took the
// count for a secret ("totalTokens":[REDACTED]): 1284 lines across the gym's
// archive stopped being JSON, so tokens, frictions and run-detail skipped every
// turn with usage and fell back to estimates.
import { redact, parseRecord } from "../scripts/factory/redact.mjs";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
const turn = (input, cacheRead) => JSON.stringify({ version: 1, recordType: "message", source: "async", agent: "factory-contract-author",
  ts: 1794616233717, timestamp: "2026-11-14T00:30:33.717Z", sourceEventType: "message_end", role: "assistant",
  usage: { input, output: 1685, cacheRead, cacheWrite: 0, cost: 0.056312 },
  message: { role: "assistant", content: [{ type: "toolCall", id: "t1", name: "read", arguments: { path: "docs/agents/factory.md" } }],
    usage: { input, output: 1685, cacheRead, cacheWrite: 0, reasoning: 15, totalTokens: input + 1685 + cacheRead, maxTokens: 4096 }, stopReason: "toolUse" } });

test("a token count is not a secret: a redacted transcript line stays JSON with its counts", () => {
  const line = turn(5653, 0);
  const out = redact(line);
  assert.doesNotThrow(() => JSON.parse(out), out.slice(0, 200));
  assert.equal(JSON.parse(out).message.usage.totalTokens, 7338);
  assert.equal(JSON.parse(out).message.usage.maxTokens, 4096);
  for (const s of ["max_tokens=4096", "\"input_tokens\": 12", "TOTAL_TOKENS=99"]) assert.equal(redact(s), s);
  // A secret still goes, numeric or not.
  assert.equal(redact("token=123456"), "token=[REDACTED]");
  assert.equal(redact("\"api_key\": 98765"), "\"api_key\": [REDACTED]");
});

test("a line archived before the fix is read again: the redacted count becomes null, the rest is kept", () => {
  const old = turn(5653, 0).replace(/"totalTokens":\d+/, "\"totalTokens\":[REDACTED]");
  assert.throws(() => JSON.parse(old));
  const r = parseRecord(old);
  assert.equal(r.message.usage.input, 5653);
  assert.equal(r.message.usage.totalTokens, null);
  assert.equal(parseRecord("not json"), null);
  assert.equal(parseRecord("{\"text\":\"a [REDACTED] word\"}").text, "a [REDACTED] word");

  const dir = mkdtempSync(join(tmpdir(), "tokens-"));
  mkdirSync(join(dir, "r1"));
  writeFileSync(join(dir, "r1", "run.json"), JSON.stringify({ run: "47ac94a6", agent: "factory-contract-author", model: "or/anthropic/claude-opus-5.5:high",
    usage: { input: 11653, output: 3370, cacheRead: 0, cacheWrite: 0, turns: 2 } }));
  writeFileSync(join(dir, "r1", "transcript.jsonl"), [old, turn(6000, 0).replace(/"totalTokens":\d+/, "\"totalTokens\":[REDACTED]")].join("\n") + "\n");
  const j = JSON.parse(execFileSync(process.execPath, [new URL("../scripts/factory/tokens.mjs", import.meta.url).pathname, dir, "--json"], { encoding: "utf8" }));
  assert.equal(j.runs[0].estimated, false, "the turns were read, not estimated");
  assert.equal(j.runs[0].turns, 2);
  assert.equal(j.runs[0].peak, 6000);
});
