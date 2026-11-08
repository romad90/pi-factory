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
