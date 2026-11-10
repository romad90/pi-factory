// The cockpit's contract (D119): what every view reads, derived from the
// snapshot status.mjs builds from the mission's files. Pure: no file, no git,
// no clock, so a cloud deployment can serve the same JSON from the same
// records, and a test can feed it any snapshot.
//
// v1 adds, on top of the snapshot:
//   contract: 1
//   waitingOn: { who: "you" | "factory" | "lead" | "nobody", text, mission?, count? }
//   inbox: [card]   one card per thing a person must decide, oldest first
//   missions[].phase: "needs-you" | "running" | "lead" | "closed" | "parked"
//   missions[].span: { start, end, runs, cost, calls, refused } over the archived runs
//   health: { missions: [{ name, cost, decisions, runs, refused, rounds }], guard: { total, refused,
//            allowed, unknown, byRule: [{ rule, total, allowed, refused, unknown }] }, causes: { byClass, open } }
//   roles: lane order for timelines (the mission's runs carry role, start, end,
//          model, cost, calls and refusals: missions[].timeline)
// A card: { id, mission, kind, ticket, title, question, since,
//           options: [{ label, effect, command, suggested }],
//           evidence: [{ label, text, path }] }
// `command` is text to copy: the cockpit never runs anything (read-only, P10).

export const CONTRACT_VERSION = 1;

const q = (s) => `"${s}"`;
const lastEvent = (m) => (m.log && m.log[0] ? m.log[0].date : null);
const paths = (text) => [...new Set(String(text || "").match(/(?:\.scratch|\.factory|docs)\/[\w./-]+\.(?:md|tsv|json)/g) || [])];
const pathEvidence = (m) => paths(m.next).map((p) => ({ label: p.split("/").pop(), text: "", path: p }));

// Each verdict copy of a ticket is a round: what it said is the evidence.
function roundEvidence(m, t) {
  const rounds = t.history?.length ? t.history : t.verdict ? [t.verdict] : [];
  return rounds.map((v) => ({
    label: `r${v.round ?? "?"} ${v.result || "?"}`,
    text: v.blocking || (v.result === "PASS" ? "" : "no blocking finding recorded"),
    path: `${m.factoryDir || ".scratch"}/${m.name}/verdicts/${v.file || ""}`,
  }));
}

function ticketCard(m, t, why) {
  const n = t.history?.length || t.round || 0;
  const options = [];
  if (t.integrated) options.push({
    label: "Review it again",
    effect: "Its integrated code stands. The verdict is set aside, no round is counted, and the ticket goes back to review.",
    command: `/factory-rereview ${m.name} ${t.name} ${q("<what changed since the review, or why it judged nothing>")}`,
    suggested: true,
  });
  options.push({
    label: "Rebuild it from round 1",
    effect: "Verdicts and integration marker are removed; a worker builds it again. Integrated code stays in git until you revert it.",
    command: `scripts/factory/reset-ticket.sh ${m.name} ${t.name} ${q("<why>")}`,
    suggested: !t.integrated,
  });
  options.push({
    label: "Amend the contract",
    effect: "When the ticket asks for the wrong thing: the contract author changes it, you approve it again (G1).",
    command: `/factory-amend ${m.name} ${q("<the change>")}`,
    suggested: false,
  });
  return {
    id: `${m.name}:ticket:${t.name}`, mission: m.name, kind: why, ticket: t.name,
    title: why === "no-progress" ? "Ticket makes no progress" : "Ticket out of rounds",
    question: `Ticket ${t.num || t.name} failed ${n} review round${n === 1 ? "" : "s"}${why === "no-progress" ? ", the last one like the one before" : ""}. What should the factory do?`,
    options, evidence: roundEvidence(m, t), since: lastEvent(m),
  };
}

// The human steps of next.sh (HUMAN_STEPS): the question, and what each
// answer does. Anything not listed falls back to next.sh's own sentence.
const STEPS = {
  decide: (m) => ({ title: "Question from the factory", question: (m.question || "").split("\n").find((l) => l.trim() && !/^(#|\*\*[\w ]+:\*\*)/.test(l.trim()))?.trim() || "The factory has a question.",
    options: [
      // D124: a worker asking to install or change a manifest: a person does it, then records it.
      ...(/install|dependenc|package\.json|lock ?file|package-lock/i.test(m.question || "") ? [{ label: "Change the dependencies yourself, then record it",
        effect: "Workers never install (D65). Commit the change (manifest and lockfile), then record it: reviewers count those files as delivered, and test-on-base skips a base that can't run with the new packages.",
        command: `/factory-deps ${m.name} ${q("<what you changed>")}`, suggested: true }] : []),
      { label: "Answer", effect: "Recorded in decisions.tsv; the factory carries on from where it stopped. Irreversible choices never default (D47).", command: `/factory-decide ${m.name} ${q("<your answer, and why>")}`, suggested: !/install|dependenc|package\.json|lock ?file|package-lock/i.test(m.question || "") }],
    evidence: [{ label: "open-question.md", text: (m.question || "").slice(0, 600), path: `${m.factoryDir || ".scratch"}/${m.name}/state/open-question.md` }] }),
  approve: (m) => {
    // The critique's findings are the evidence; a blocking one makes Amend the suggestion.
    const c = m.critique, blocking = (c?.findings || []).filter((f) => f.level === "blocking").length;
    // D126: from round 3, only a blocking finding that names a wrong change
    // that would pass keeps Amend the suggestion.
    const round = c?.round || 1, real = (c?.findings || []).filter((f) => f.level === "blocking" && f.passes).length;
    const amend = blocking > 0 && (round < 3 || real > 0);
    const evidence = (c?.findings || []).map((f) => ({ label: `${f.id} ${f.level}`, level: f.level,
      text: `${f.title}. ${f.text}${f.passes ? `\nPasses wrongly: ${f.passes}` : f.level === "blocking" && round >= 3 ? "\n(names no wrong change that would pass)" : ""}${f.fix ? `\nFix: ${f.fix}` : ""}`,
      path: `${m.factoryDir || ".scratch"}/${m.name}/contract-critique.md` }));
    if (c && !c.afterContract) evidence.unshift({ label: "stale", level: "blocking", text: "The critique is older than the contract: the critic hasn't judged this version.", path: "" });
    return { title: "Contract (G1)",
      question: `Approve the contract of ${m.name}?${round > 1 ? ` Round ${round}.` : ""} ${m.contract?.total ?? "?"} assertions; the critic found ${blocking} blocking and ${(c?.findings || []).length - blocking} non-blocking problem${(c?.findings || []).length - blocking === 1 ? "" : "s"}.`,
      options: [
        { label: "Approve", effect: `The tickets are written next; you approve them before any build.${blocking ? " Approving accepts the open findings; it is recorded." : ""}`, command: `/factory-approve ${m.name}`, suggested: !amend },
        { label: "Amend", effect: `The contract author rewrites it with your change, the critic reads it again, you approve again.${blocking ? " Answer the blocking findings in your change." : ""}`, command: `/factory-amend ${m.name} ${q("<the change>")}`, suggested: amend }],
      evidence };
  },
  "approve-tickets": (m) => ({ title: "Tickets", question: `Approve the ${m.counts?.total ?? ""} tickets of ${m.name}? Edit, split or delete them first if you like.`.replace("  ", " "),
    evidence: (m.tickets || []).map((t) => ({ label: t.num || t.name, text: `${t.title || t.name}${t.size ? ` · size ${t.size}` : ""}${t.covers?.length ? ` · covers ${t.covers.join(", ")}` : ""}${t.blockedBy?.length ? ` · after ${t.blockedBy.join(", ")}` : ""}`,
      path: `${m.factoryDir || ".scratch"}/${m.name}/issues/${t.name}.md` })),
    options: [{ label: "Approve", effect: "Workers start on the tickets with no blocker.", command: `/factory-approve ${m.name} tickets`, suggested: true },
      { label: "Edit, then approve", effect: "Change the files under issues/ yourself; the coverage check (G2) runs again.", command: "", suggested: false }] }),
  coverage: (m) => ({ title: "Coverage (G2)", question: "The tickets don't cover every assertion of the contract.",
    options: [{ label: "Fix the tickets", effect: "Add the missing ids to '## Covers'; G2 runs again.", command: "", suggested: true },
      { label: "Amend the contract", effect: "If an assertion should go, the contract changes and you approve it again.", command: `/factory-amend ${m.name} ${q("<the change>")}`, suggested: false }] }),
  setup: () => ({ title: "Project setup", question: "The factory has no test command for this project, and never integrates without tests (D44).",
    options: [{ label: "Find and rehearse the commands", effect: "Writes .factory/commands.env after running them; commit it.", command: "factory setup --write", suggested: true }] }),
  unverified: (m) => ({ title: "Unverified assertions", question: "A gate passed but left assertions unproven.",
    options: [{ label: "Prove them", effect: "Add a test or a check; the gate runs again.", command: "", suggested: true },
      { label: "Ship them as known limits", effect: "Listed under Known limits in the MR.", command: `/factory-accept-unverified ${m.name} ${q("<ids|ALL>")} ${q("<why>")}`, suggested: false }] }),
  pr: (m) => ({ title: "Ready for the MR", question: `${m.name} passed its gates. Open the merge request?`,
    options: [{ label: "Write the evidence, open the MR", effect: "/pr writes pr.md; mr.sh opens the MR and records mr.url, which closes the mission.", command: `/pr`, suggested: true },
      { label: "Close it without an MR", effect: "Records why in mr.url; the mission stops asking.", command: `scripts/factory/mr.sh ${m.name} --local ${q("<why>")}`, suggested: false }] }),
  paused: (m) => ({ title: "Paused", question: `${m.name} is paused.`,
    options: [{ label: "Resume", effect: "Shows where it stopped; then next.sh carries on.", command: `scripts/factory/pause.sh resume ${m.name}`, suggested: true }] }),
};

function stepCard(m) {
  const make = STEPS[m.step];
  const base = make ? make(m) : {
    title: m.step, question: m.next,
    options: [{ label: "Do what the factory asks", effect: "", command: (String(m.next).match(/\/factory-[a-z-]+[^.;]*|scripts\/factory\/[\w-]+\.sh[^.;,]*/) || [""])[0].trim(), suggested: true }],
  };
  const evidence = [...(base.evidence || []), ...pathEvidence(m).filter((e) => !(base.evidence || []).some((b) => b.path === e.path))];
  return { id: `${m.name}:step:${m.step}`, mission: m.name, kind: m.step, ticket: "", ...base, evidence, factorySays: m.next, since: lastEvent(m) };
}

// The contract critic's file (contract-critique.md): its result and each
// finding with its level, what it says and the suggested fix.
export function parseCritique(t) {
  const firstWord = (x) => (x || "").trim().split(/\s+/)[0] || "";
  const field = (text, name) => (text.match(new RegExp(`^\\*\\*${name}:\\*\\*\\s*(.+)$`, "m")) || [])[1]?.trim() || "";
  const findings = [];
  // The critic writes the level in the heading ("### F6 — [blocking] …",
  // "### 1. [blocking] …") or as the finding's first bullet ("- [blocking] …"):
  // all seen (deps-node-22, eslint-10).
  const re = /^###\s+(F\d+|\d+)\.?\s*[—–-]*\s*(?:\[(blocking|non-blocking)\]\s*)?(.+)$/gm;
  let m; const at = [];
  while ((m = re.exec(t))) at.push({ id: m[1], level: m[2] || "", title: m[3].trim(), start: re.lastIndex, head: m.index });
  at.forEach((a, i) => {
    let body = t.slice(a.start, i + 1 < at.length ? at[i + 1].head : undefined).split(/\n## /)[0].trim();
    const tag = body.match(/^\s*[-*]?\s*\[(blocking|non-blocking)\]\s*/m);
    const level = a.level || (tag ? tag[1] : "unknown");
    if (tag) body = body.replace(tag[0], "");
    // D126: the concrete wrong change the finding lets pass, on its own line.
    const passes = (body.match(/^\s*[-*]?\s*Passes wrongly:\s*(.+)$/im) || [])[1]?.trim() || "";
    const full = body.trim();
    body = body.replace(/^\s*[-*]?\s*Passes wrongly:.*$/im, "");
    const paras = body.split(/\n\s*\n/).map((x) => x.replace(/\s+/g, " ").trim()).filter(Boolean);
    // D130: the whole finding (Markdown) for the gate page, and the assertions it names.
    const refs = [...new Set((a.title + "\n" + full).match(/VAL-[A-Z0-9]+-\d{3}/g) || [])];
    findings.push({ id: a.id, level, title: a.title, passes: passes.slice(0, 400), text: (paras.find((x) => !/^Suggested fix:/i.test(x)) || "").slice(0, 700),
      fix: (paras.find((x) => /^Suggested fix:/i.test(x)) || "").replace(/^Suggested fix:\s*/i, "").slice(0, 500), body: full.slice(0, 6000), refs });
  });
  return { result: firstWord(field(t, "Critique result")), findings };
}

// An agent's final answer (output.md, or the tail of its live log): the prose,
// the fields of its report block ("```acceptance-report" or "```json" with
// the report's keys), and the lines after it. A block that doesn't parse, or a
// run still working, gives fields: null (D130).
const REPORT_KEYS = ["criteriaSatisfied", "changedFiles", "commandsRun", "residualRisks", "diffSummary", "reviewFindings", "manualNotes", "validationOutput", "status"];
export function parseReport(text) {
  const t = String(text || ""), re = /^```(acceptance-report|json)[ \t]*\n([\s\S]*?)\n```[ \t]*$/gm;
  let m, last = null;
  while ((m = re.exec(t))) {
    try { const j = JSON.parse(m[2]); if (j && typeof j === "object" && !Array.isArray(j) && REPORT_KEYS.some((k) => k in j)) last = { j, at: m.index, end: re.lastIndex }; } catch {}
  }
  if (!last) return { prose: t.trim(), fields: null, after: "" };
  return { prose: t.slice(0, last.at).trim(), fields: last.j, after: t.slice(last.end).trim() };
}

export function inbox(snapshot) {
  const cards = [];
  for (const m0 of snapshot.missions || []) {
    const m = { factoryDir: snapshot.factoryDir, ...m0, question: m0.question || (m0.needs || []).find((n) => n.kind === "question")?.text || "" };
    if (m.otherBranch) continue;
    const ticketsCarded = new Set();
    // A stuck or escalated ticket gets its own card with the rounds as evidence;
    // the mission's generic escalate step then adds nothing.
    for (const t of m.tickets || []) {
      if (t.state === "escalate" || t.stuck) { cards.push(ticketCard(m, t, t.stuck ? "no-progress" : "escalate")); ticketsCarded.add(t.name); }
    }
    if (m.human && !(m.step === "escalate" && ticketsCarded.size)) cards.push(stepCard(m));
    if (m.step !== "decide" && m.question) cards.push({ ...STEPS.decide(m), id: `${m.name}:question`, mission: m.name, kind: "question", ticket: "", since: lastEvent(m) });
    for (const w of m.workers || []) if (w.quiet) cards.push({
      id: `${m.name}:quiet:${w.run}`, mission: m.name, kind: "quiet", ticket: w.ticket || "", title: "Silent worker",
      question: `${w.agent || "A worker"} has written nothing for ${Math.round(w.ageSec / 60)} min.`,
      options: [{ label: "Look at its log", effect: "Nothing changes; the run may just be slow.", command: "", suggested: true }],
      evidence: [{ label: "last lines", text: (w.last || []).slice(-5).join("\n"), path: "" }], since: lastEvent(m),
    });
  }
  return cards.sort((a, b) => String(a.since || "").localeCompare(String(b.since || "")));
}

export function phase(m, cards) {
  if (m.otherBranch) return "parked";
  if (m.mr || m.step === "closed" || m.step === "mr-open") return "closed";
  if (cards.some((c) => c.mission === m.name)) return "needs-you";
  if ((m.workers || []).some((w) => !w.done)) return "running";
  return "lead";
}

export function waitingOn(snapshot, cards) {
  if (cards.length) {
    const c = cards[0];
    return { who: "you", count: cards.length, mission: c.mission, text: `${c.mission}${c.ticket ? " · " + c.ticket : ""}: ${c.title.toLowerCase()}` };
  }
  const live = (snapshot.missions || []).flatMap((m) => (m.workers || []).filter((w) => !w.done).map((w) => ({ m, w })));
  if (live.length) return { who: "factory", count: live.length, mission: live[0].m.name, text: `${live[0].w.agent || "an agent"}${live[0].w.ticket ? " on " + live[0].w.ticket : ""} in ${live[0].m.name}` };
  const open = (snapshot.missions || []).find((m) => !m.otherBranch && !m.mr && m.step && m.step !== "closed" && m.step !== "mr-open");
  if (open) return { who: "lead", count: 1, mission: open.name, text: `${open.name}: nothing runs; the lead's next step is ${open.step}` };
  return { who: "nobody", count: 0, text: "no open mission" };
}

// Lanes, in the order work flows through a mission; unknown roles go last.
export const ROLES = ["contract-author", "contract-critic", "architect", "strategy-critic", "designer", "investigator", "explorer",
  "ticket-writer", "worker", "worker-heavy", "reviewer", "review-axis", "validator", "code-steward"];

export function span(timeline) {
  const t = timeline || [];
  if (!t.length) return null;
  return {
    start: t.reduce((a, r) => (r.start < a ? r.start : a), t[0].start), end: t.reduce((a, r) => (r.end > a ? r.end : a), t[0].end),
    runs: t.length, cost: Math.round(t.reduce((a, r) => a + (r.cost || 0), 0) * 100) / 100,
    calls: t.reduce((a, r) => a + (r.calls || 0), 0), refused: t.reduce((a, r) => a + (r.refused || []).length, 0),
  };
}

// D122: the factory engineer's view across missions: what each mission cost
// you and the model, the guard's refusals judged again today (allowed today =
// fixed since), and the causes the learning loop classified.
export function health(snapshot) {
  const ms = snapshot.missions || [];
  const missions = ms.map((m) => {
    const s = span(m.timeline);
    return { name: m.name, phase: m.phase || "", cost: s ? s.cost : m.usage?.cost || 0, decisions: m.interventions?.human || 0,
      runs: s ? s.runs : 0, refused: s ? s.refused : 0, rounds: (m.tickets || []).reduce((a, t) => a + (t.round || 0), 0) };
  });
  const refusals = ms.flatMap((m) => (m.timeline || []).flatMap((r) => r.refused || []));
  const byRule = new Map();
  for (const g of refusals) {
    const e = byRule.get(g.rule) || { rule: g.rule, total: 0, allowed: 0, refused: 0, unknown: 0 };
    e.total++; e[g.today === "allowed" || g.today === "refused" ? g.today : "unknown"]++; byRule.set(g.rule, e);
  }
  const count = (k) => refusals.filter((g) => g.today === k).length;
  const causes = snapshot.causes || [];
  const byClass = {};
  for (const c of causes) byClass[c.class || "other"] = (byClass[c.class || "other"] || 0) + 1;
  return {
    missions,
    guard: { total: refusals.length, refused: count("refused"), allowed: count("allowed"), unknown: refusals.length - count("refused") - count("allowed"),
      byRule: [...byRule.values()].sort((a, b) => b.total - a.total) },
    causes: { total: causes.length, byClass, open: causes.filter((c) => /^open/i.test(c.status)).length },
  };
}

export function toContract(snapshot) {
  const cards = inbox(snapshot);
  const missions = (snapshot.missions || []).map((m) => ({ ...m, phase: phase(m, cards), span: span(m.timeline) }));
  return {
    contract: CONTRACT_VERSION, ...snapshot,
    waitingOn: waitingOn(snapshot, cards), inbox: cards, roles: ROLES, missions,
    health: health({ ...snapshot, missions }), causes: snapshot.causes || [],
  };
}
