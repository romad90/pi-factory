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
    options: [{ label: "Answer", effect: "Recorded in decisions.tsv; the factory carries on from where it stopped. Irreversible choices never default (D47).", command: `/factory-decide ${m.name} ${q("<your answer, and why>")}`, suggested: true }],
    evidence: [{ label: "open-question.md", text: (m.question || "").slice(0, 600), path: `${m.factoryDir || ".scratch"}/${m.name}/state/open-question.md` }] }),
  approve: (m) => ({ title: "Contract (G1)", question: `Approve the contract of ${m.name}? ${m.contract?.total ?? "?"} assertions.`,
    options: [
      { label: "Approve", effect: "The tickets are written next; you approve them before any build.", command: `/factory-approve ${m.name}`, suggested: true },
      { label: "Amend", effect: "The contract author rewrites it with your change; you approve again.", command: `/factory-amend ${m.name} ${q("<the change>")}`, suggested: false }] }),
  "approve-tickets": (m) => ({ title: "Tickets", question: `Approve the ${m.counts?.total ?? ""} tickets of ${m.name}? Edit, split or delete them first if you like.`.replace("  ", " "),
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

export function toContract(snapshot) {
  const cards = inbox(snapshot);
  return {
    contract: CONTRACT_VERSION, ...snapshot,
    waitingOn: waitingOn(snapshot, cards), inbox: cards,
    missions: (snapshot.missions || []).map((m) => ({ ...m, phase: phase(m, cards) })),
  };
}
