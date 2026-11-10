// The cockpit contract (D119): every question a person had to ask the lead
// in mission server-survives-bad-input must be answered by the snapshot.
// Run: node --test tests/cockpit-contract.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { CONTRACT_VERSION, inbox, phase, toContract, waitingOn } from "../scripts/factory/cockpit-contract.mjs";

const v = (round, result, blocking = "") => ({ round, result, blocking, file: `03-x-code.r${round}.md`, commit: "", brief: "", model: "" });
const mission = (over) => ({
  name: "m", title: "", step: "build", next: "", human: false, otherBranch: "", paused: false, mr: "",
  contract: { total: 4, approved: true }, counts: { total: 0 }, tickets: [], needs: [], workers: [], log: [{ date: "2026-11-08T17:50:00Z" }], ...over,
});
// The stop at ticket 03: three FAIL rounds, the first refused by the guard.
const stuck = mission({
  name: "server-survives-bad-input", step: "escalate", human: true,
  next: "human: 03-x failed 3 rounds. Usually the contract or spec is wrong: consider 'workflow.sh contract' (amend).",
  tickets: [
    { name: "01-a", num: "01", state: "pass", round: 1, integrated: "abc", history: [v(1, "PASS")] },
    { name: "03-x", num: "03", state: "escalate", round: 3, integrated: "def", stuck: false,
      history: [v(1, "FAIL", "checks unverified: guard refused the test run ($PWD)"), v(2, "FAIL", "no patch"), v(3, "FAIL", "no patch")] },
  ],
});

test("a stuck ticket is one card: the question, the options with what each does, the rounds as evidence, a command to copy", () => {
  const cards = inbox({ factoryDir: ".scratch", missions: [stuck] });
  assert.equal(cards.length, 1, "the mission's escalate step adds no second card");
  const [c] = cards;
  assert.equal(c.ticket, "03-x");
  assert.match(c.question, /failed 3 review rounds/);
  assert.deepEqual(c.evidence.map((e) => e.label), ["r1 FAIL", "r2 FAIL", "r3 FAIL"]);
  assert.match(c.evidence[0].text, /guard refused/);
  assert.equal(c.evidence[0].path, ".scratch/server-survives-bad-input/verdicts/03-x-code.r1.md");
  const suggested = c.options.filter((o) => o.suggested);
  assert.equal(suggested.length, 1);
  assert.equal(suggested[0].command, `/factory-rereview server-survives-bad-input 03-x "<what changed since the review, or why it judged nothing>"`);
  for (const o of c.options) assert.ok(o.effect, `${o.label} says what it does`);
});

test("an open question shows its first line and the decide command", () => {
  const m = mission({ step: "decide", human: true, needs: [{ kind: "decide", text: "" }, { kind: "question", text: "# Q\n**Ticket:** 02-b\n\nKeep the old logger or swap it?\nmore" }] });
  const [c] = inbox({ missions: [m] });
  assert.equal(c.question, "Keep the old logger or swap it?");
  assert.equal(c.options[0].command, `/factory-decide m "<your answer, and why>"`);
});

test("every human step of next.sh gets a card with at least one option", () => {
  const steps = ["paused", "grill", "approve-strategy", "job-done", "verify-failed", "approve-conclusion", "handoff", "report", "approve", "approve-design", "decide", "approve-tickets", "coverage", "setup", "escalate", "blocked", "unverified", "pr"];
  for (const step of steps) {
    const [c] = inbox({ missions: [mission({ step, human: true, next: `human: /factory-approve m ${step}. Then next.sh` })] });
    assert.ok(c, step);
    assert.ok(c.question && c.options.length, `${step}: question and options`);
  }
});

test("phase: mr.url closes a mission whatever step it last showed; a running worker is running; else it's the lead's turn", () => {
  assert.equal(phase(mission({ step: "health", mr: "https://example/mr/1" }), []), "closed");
  assert.equal(phase(mission({ step: "closed" }), []), "closed");
  assert.equal(phase(mission({ workers: [{ done: false }] }), []), "running");
  assert.equal(phase(mission({}), []), "lead");
  assert.equal(phase(mission({ otherBranch: "b" }), []), "parked");
  assert.equal(phase(stuck, inbox({ missions: [stuck] })), "needs-you");
});

test("waitingOn answers \"what are we waiting for?\" in one line", () => {
  const snap = (missions) => ({ missions });
  assert.equal(waitingOn(snap([stuck]), inbox(snap([stuck]))).who, "you");
  const run = mission({ workers: [{ done: false, agent: "factory-worker", ticket: "02-b" }] });
  assert.deepEqual(waitingOn(snap([run]), []), { who: "factory", count: 1, mission: "m", text: "factory-worker on 02-b in m" });
  assert.equal(waitingOn(snap([mission({})]), []).who, "lead");
  assert.equal(waitingOn(snap([mission({ mr: "x" })]), []).who, "nobody");
});

test("toContract keeps the snapshot and adds the versioned fields", () => {
  const c = toContract({ generated: "t", factoryDir: ".scratch", factory: null, bench: [], missions: [stuck] });
  assert.equal(c.contract, CONTRACT_VERSION);
  assert.equal(c.generated, "t");
  assert.equal(c.missions[0].phase, "needs-you");
  assert.equal(c.inbox.length, 1);
  assert.equal(c.waitingOn.who, "you");
});

test("span sums the archived runs: wall time, cost, tool calls, refusals", async () => {
  const { span } = await import("../scripts/factory/cockpit-contract.mjs");
  assert.equal(span([]), null);
  const s = span([
    { start: "2026-11-08T16:13:31Z", end: "2026-11-08T16:20:24Z", cost: 0.1, calls: 53, refused: [{}] },
    { start: "2026-11-08T16:20:55Z", end: "2026-11-08T16:22:04Z", cost: 0.25, calls: 34, refused: [{}, {}, {}] },
  ]);
  assert.deepEqual(s, { start: "2026-11-08T16:13:31Z", end: "2026-11-08T16:22:04Z", runs: 2, cost: 0.35, calls: 87, refused: 4 });
});

test("health: refusals judged again today (allowed = fixed since), by rule; causes by class; cost and decisions per mission", async () => {
  const { health } = await import("../scripts/factory/cockpit-contract.mjs");
  const run = (refused, cost) => ({ start: "2026-11-08T16:00:00Z", end: "2026-11-08T16:01:00Z", cost, calls: 1, refused });
  const h = health({
    missions: [
      { name: "a", interventions: { human: 7 }, tickets: [{ round: 1 }, { round: 4 }], timeline: [run([{ rule: "strayWrite", today: "allowed" }, { rule: "strayWrite", today: "refused" }], 1.5), run([{ rule: "push", today: "refused" }], 0.5)] },
      { name: "b", interventions: { human: 2 }, tickets: [], usage: { cost: 1.32 }, timeline: [] },
    ],
    causes: [{ class: "factory_bug", status: "open" }, { class: "factory_bug", status: "fixed #133" }, { class: "model_weakness", status: "n/a" }],
  });
  assert.deepEqual(h.missions.map((m) => [m.name, m.cost, m.decisions, m.rounds, m.refused]), [["a", 2, 7, 5, 3], ["b", 1.32, 2, 0, 0]]);
  assert.deepEqual(h.guard, { total: 3, refused: 2, allowed: 1, unknown: 0, byRule: [{ rule: "strayWrite", total: 2, allowed: 1, refused: 1, unknown: 0 }, { rule: "push", total: 1, allowed: 0, refused: 1, unknown: 0 }] });
  assert.deepEqual(h.causes, { total: 3, byClass: { factory_bug: 2, model_weakness: 1 }, open: 1 });
});

test("G1: the critique's findings are the evidence, and a blocking one makes Amend the suggestion", () => {
  const critique = { result: "FINDINGS", at: "t", afterContract: true, findings: [
    { id: "F8", level: "blocking", title: "VAL-CI-001 passes with combinations excluded", text: "The matrix check reads the lists only.", fix: "Forbid exclude and include." },
    { id: "F9", level: "non-blocking", title: "Stopping test:watch is ambiguous", text: "When is it stopped?", fix: "" }] };
  const [c] = inbox({ missions: [mission({ name: "deps-node-22", step: "approve", human: true, contract: { total: 16 }, critique })] });
  assert.match(c.question, /16 assertions; the critic found 1 blocking and 1 non-blocking problem\./);
  assert.deepEqual(c.options.map((o) => [o.label, o.suggested]), [["Approve", false], ["Amend", true]]);
  assert.deepEqual(c.evidence.map((e) => e.label), ["F8 blocking", "F9 non-blocking"]);
  assert.match(c.evidence[0].text, /lists only\.\nFix: Forbid exclude/);
  const clean = inbox({ missions: [mission({ step: "approve", human: true, critique: { ...critique, findings: [critique.findings[1]] } })] })[0];
  assert.equal(clean.options.find((o) => o.suggested).label, "Approve");
  const stale = inbox({ missions: [mission({ step: "approve", human: true, critique: { ...critique, afterContract: false } })] })[0];
  assert.equal(stale.evidence[0].label, "stale", "a critique older than the contract says so first");
});

test("approve-tickets: each ticket is a line of evidence", () => {
  const [c] = inbox({ missions: [mission({ step: "approve-tickets", human: true, counts: { total: 2 },
    tickets: [{ name: "01-a", num: "01", title: "Upgrade tap", size: "M", covers: ["VAL-DEPS-001"], blockedBy: [] }, { name: "02-b", num: "02", title: "Lockfile", covers: [], blockedBy: ["01"] }] })] });
  assert.deepEqual(c.evidence.map((e) => e.text), ["Upgrade tap · size M · covers VAL-DEPS-001", "Lockfile · after 01"]);
});

test("parseCritique reads the level from the heading or from the finding's first bullet (both seen in deps-node-22)", async () => {
  const { parseCritique } = await import("../scripts/factory/cockpit-contract.mjs");
  const c = parseCritique([
    "**Critique result:** FINDINGS", "", "## Findings", "",
    "### F6 — [blocking] VAL-TEST-006 can pass when a script never starts tap", "", "A script can fail before tap starts.", "", "Suggested fix: require each script to start tap 21.", "",
    "### F1 — CI matrix lists do not prove that CI runs all required combinations", "", "- [blocking] VAL-CI-001 checks the lists only.", "", "Suggested fix: Require all four combinations.", "",
    "### F2 — The watch stop point has two readings", "", "- [non-blocking] Stop after start, or after results?", "", "## Review limits", "None.",
  ].join("\n"));
  assert.equal(c.result, "FINDINGS");
  assert.deepEqual(c.findings.map((f) => [f.id, f.level, f.text, f.fix]), [
    ["F6", "blocking", "A script can fail before tap starts.", "require each script to start tap 21."],
    ["F1", "blocking", "VAL-CI-001 checks the lists only.", "Require all four combinations."],
    ["F2", "non-blocking", "Stop after start, or after results?", ""],
  ]);
});

test("D124: a worker's question about installing suggests the person's dependency step", () => {
  const m = mission({ name: "deps-node-22", step: "decide", human: true, question: "**Ticket:** 01-tap\n\nSomeone has to run npm install and write package-lock.json: may I?" });
  const [c] = inbox({ missions: [m] });
  assert.equal(c.options[0].command, `/factory-deps deps-node-22 "<what you changed>"`);
  assert.equal(c.options.find((o) => o.suggested).label, "Change the dependencies yourself, then record it");
});

test("D126: from round 3, a blocking finding that names no wrong change that would pass doesn't keep Amend suggested", async () => {
  const { parseCritique } = await import("../scripts/factory/cockpit-contract.mjs");
  const text = (passes) => ["**Critique result:** FINDINGS", "", "### F1 — Matrix entries need not control the test environment", "", "- [blocking] VAL-CI-001 checks matrix entries only.",
    ...(passes ? ["", "Passes wrongly: a run_tests job that hard-codes runs-on: ubuntu-latest."] : []), "", "Suggested fix: require runs-on to use the matrix.", "", "## Review limits"].join("\n");
  const card = (round, passes) => inbox({ missions: [mission({ step: "approve", human: true, contract: { total: 16 },
    critique: { ...parseCritique(text(passes)), round, afterContract: true } })] })[0];
  assert.equal(card(2, false).options.find((o) => o.suggested).label, "Amend", "rounds 1 and 2: any blocking finding");
  assert.equal(card(5, true).options.find((o) => o.suggested).label, "Amend", "a wrong change that would pass keeps it blocking");
  const late = card(5, false);
  assert.equal(late.options.find((o) => o.suggested).label, "Approve");
  assert.match(late.question, /Round 5\./);
  assert.match(late.evidence[0].text, /names no wrong change that would pass/);
  assert.match(card(5, true).evidence[0].text, /Passes wrongly: a run_tests job that hard-codes/);
});

test("parseCritique reads numbered findings (\"### 1. [blocking] …\", eslint-10) and keeps each body and the assertions it names", async () => {
  const { parseCritique } = await import("../scripts/factory/cockpit-contract.mjs");
  const { readFileSync } = await import("node:fs");
  const c = parseCritique(readFileSync(new URL("./fixtures/gate/eslint-10/contract-critique.md", import.meta.url), "utf8"));
  assert.equal(c.result, "FINDINGS");
  assert.deepEqual(c.findings.map((f) => [f.id, f.level]), [["1", "blocking"], ["2", "blocking"], ["3", "non-blocking"]]);
  assert.match(c.findings[0].title, /^Unsampled source files can lose `no-shadow`/);
  assert.match(c.findings[0].passes, /"warn"` for `lib\/url\.js` only/);
  assert.match(c.findings[1].fix, /^Restrict the override/);
  assert.equal(c.findings[2].passes, "");
  assert.deepEqual(c.findings[0].refs, ["VAL-CONF-001", "VAL-CONF-003"]);
  assert.match(c.findings[0].body, /^`VAL-CONF-001` checks only four files\./);
  assert.doesNotMatch(c.findings[2].body, /## Review limits/);
});

test("parseReport reads an agent's final answer: the prose, its acceptance-report fields, and what follows (deps-node-22 heavy worker)", async () => {
  const { parseReport } = await import("../scripts/factory/cockpit-contract.mjs");
  const { readFileSync } = await import("node:fs");
  const text = readFileSync(new URL("./fixtures/reports/worker-heavy.md", import.meta.url), "utf8");
  const r = parseReport(text);
  assert.match(r.prose, /^`npm test` now runs the whole suite on tap 21/);
  assert.doesNotMatch(r.prose, /acceptance-report|criteriaSatisfied/);
  assert.equal(r.fields.diffSummary.slice(0, 15), "tap 21 setup: e");
  assert.equal(r.fields.changedFiles.length, 8);
  assert.equal(r.fields.commandsRun[0].result, "passed");
  assert.equal(r.fields.residualRisks.length, 4);
  assert.match(r.after, /^I skipped `npm ci`/);
  // A live log's tail: tool lines before, the report at the end; a cut JSON is no report.
  const live = parseReport("[tool] bash npm test\nok 12\n" + text);
  assert.equal(live.fields.changedFiles.length, 8);
  assert.equal(parseReport("```acceptance-report\n{\"diffSummary\": \"cut").fields, null);
  assert.equal(parseReport("still working: running npm test").fields, null);
  // The older shape: a plain ```json block with the same keys (eslint-10's contract author and critic).
  const j = parseReport("Done.\n```json\n{\"diffSummary\": \"Added a contract\", \"reviewFindings\": [\"blocking: x\", \"non-blocking: y\"], \"manualNotes\": \"n\"}\n```\n");
  assert.deepEqual(j.fields.reviewFindings, ["blocking: x", "non-blocking: y"]);
  assert.equal(j.prose, "Done.");
});
