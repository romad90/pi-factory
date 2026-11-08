#!/usr/bin/env node
// The learning loop's raw material (P26): every tool call of a project's
// missions, the guard's refusals among them, lost rounds, lead deviations and
// human messages, read from the records themselves, never from retros (those
// are learn.mjs's input: the digested layer).
//
//   node learn-records.mjs events <project-dir> <out-dir>
//       writes <out-dir>/calls.json and <out-dir>/events.tsv: one row per guard
//       refusal, lost round, lead deviation and human message, with a cause
//       hint and the record it came from
//   node learn-records.mjs replay <out-dir>
//       re-runs every recorded refusal through the current guard, in the
//       context it ran in (a worker's worktree or the project), and prints
//       the ones still refused: a fix candidate, or a true block
//
// Sources: the lead's Pi sessions (learn-loop.sh copies them to
// .git/pi-factory/lead-sessions), the run archive (.git/pi-factory/archive/
// <mission>/<run>/transcript.jsonl) and .scratch/<mission>/verdicts/*.rN.md.
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { check } from "./guard-rules.mjs";

const ls = (d) => (existsSync(d) ? readdirSync(d) : []);
const records = (f) => readFileSync(f, "utf8").split("\n").filter(Boolean)
  .map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
const text = (c) => (Array.isArray(c) ? c.map((x) => x?.text ?? "").join(" ") : String(c ?? ""));
const REFUSED = /blocked by the factory guard/;

function calls(project) {
  const pf = join(project, ".git", "pi-factory");
  const files = [
    ...ls(join(pf, "lead-sessions")).filter((f) => f.endsWith(".jsonl")).map((f) => ({ f: join(pf, "lead-sessions", f), who: "lead", mission: null })),
    ...ls(join(pf, "archive")).flatMap((m) => ls(join(pf, "archive", m)).map((r) => ({ f: join(pf, "archive", m, r, "transcript.jsonl"), who: r.split("_").slice(1).join("_"), mission: m }))),
  ].filter((x) => existsSync(x.f));
  const out = [];
  for (const { f, who, mission } of files) {
    const byId = new Map();
    for (const r of records(f)) {
      const ts = r.timestamp ?? "";
      if (r.recordType === "tool_start") {             // pi-subagents transcript
        let args; try { args = JSON.parse(r.argsPayload ?? "{}"); } catch { args = { _preview: r.argsPreview }; }
        byId.set(r.toolCallId, { ts, who, mission, run: basename(f), tool: r.toolName, args });
        continue;
      }
      const m = r.message ?? {};                       // Pi session
      if (Array.isArray(m.content)) for (const c of m.content) {
        if (c?.type === "toolCall") byId.set(c.id, { ts, who, mission, run: basename(f), tool: c.name, args: c.arguments ?? {} });
      }
      if (m.role === "toolResult") {
        const k = m.toolCallId ?? r.toolCallId;
        if (byId.has(k)) Object.assign(byId.get(k), { result: text(m.content).slice(0, 600), isError: !!m.isError });
      }
    }
    out.push(...byId.values());
  }
  return out;
}

function humanMessages(project) {
  const d = join(project, ".git", "pi-factory", "lead-sessions");
  return ls(d).filter((f) => f.endsWith(".jsonl")).flatMap((f) => records(join(d, f))
    .filter((r) => r.message?.role === "user")
    .map((r) => ({ ts: r.timestamp, text: text(r.message.content).replace(/\s+/g, " ").slice(0, 200) })));
}

function lostRounds(project) {
  const s = join(project, ".scratch");
  const missions = [...ls(s).filter((m) => m !== "light").map((m) => join(s, m)), ...ls(join(s, "light")).map((m) => join(s, "light", m))];
  const out = [];
  for (const m of missions) for (const v of ls(join(m, "verdicts")).filter((f) => /\.r\d+\.md$/.test(f))) {
    const body = readFileSync(join(m, "verdicts", v), "utf8");
    if (!/^\*\*Result:\*\*\s*FAIL/m.test(body)) continue;
    const brief = ((body.match(/^\*\*Brief:\*\*\s*(.+)$/m) ?? [])[1] ?? "").trim();
    const first = (body.match(/^- \[blocking\].*$/m) ?? [""])[0].slice(0, 220);
    out.push({ mission: basename(m), verdict: v, brief, first });
  }
  return out;
}

// A first guess from what the record says; a person or the nightly run
// confirms or corrects it in taxonomy.tsv.
const hint = (brief, first) =>
  /factory guard/i.test(first) ? "factory_bug?: guard refusal"
  : /^(integrate|worker-no-patch|patch-guard|test-on-base)$/.test(brief) ? `factory_check: ${brief}`
  : "review finding: read it";

const [cmd, a, b] = process.argv.slice(2);
if (cmd === "events") {
  const project = a, out = b; mkdirSync(out, { recursive: true });
  const all = calls(project);
  writeFileSync(join(out, "calls.json"), JSON.stringify(all));
  const rows = [["kind", "when", "who", "mission", "what", "cause_hint", "record"]];
  for (const c of all.filter((x) => REFUSED.test(x.result ?? ""))) {
    rows.push(["guard_refusal", c.ts, c.who, c.mission ?? "-", JSON.stringify(c.tool === "bash" ? c.args.command : c.args).slice(0, 200), "factory_bug?: guard refusal", c.run]);
  }
  for (const r of lostRounds(project)) rows.push(["lost_round", "-", "-", r.mission, r.first || r.brief, hint(r.brief, r.first), `${r.mission}/verdicts/${r.verdict}`]);
  for (const c of all.filter((x) => x.who === "lead" && x.tool === "subagent" && (x.args.action === "steer" || x.args.action === "resume" || x.args.async === true))) {
    rows.push(["lead_deviation", c.ts, "lead", "-", JSON.stringify({ ...c.args, task: undefined, message: undefined }).slice(0, 200), "lead_deviation: subagent call outside the generated workflow", c.run]);
  }
  for (const c of all.filter((x) => x.who === "lead" && x.tool === "bash" && /\bexport FACTORY_[A-Z_]+=|(^|[;&|]\s*)FACTORY_[A-Z_]+=\S+\s+\S/.test(x.args.command ?? ""))) {
    rows.push(["lead_deviation", c.ts, "lead", "-", ((c.args.command ?? "").match(/FACTORY_[A-Z_]+=\S+/) ?? [""])[0], "lead_deviation: a factory setting overridden in its shell", c.run]);
  }
  for (const h of humanMessages(project)) rows.push(["human_message", h.ts, "human", "-", h.text, "classify: gate | decision | intervention", "lead-sessions"]);
  writeFileSync(join(out, "events.tsv"), rows.map((r) => r.map((x) => String(x ?? "").replace(/[\t\n]/g, " ")).join("\t")).join("\n") + "\n");
  const n = (k) => rows.filter((r) => r[0] === k).length;
  console.log(`${all.length} tool calls: ${n("guard_refusal")} guard refusals, ${n("lost_round")} lost rounds, ${n("lead_deviation")} lead deviations, ${n("human_message")} human messages → ${join(out, "events.tsv")}`);
} else if (cmd === "replay") {
  const all = JSON.parse(readFileSync(join(a, "calls.json"), "utf8")).filter((x) => REFUSED.test(x.result ?? ""));
  // The contexts calls ran in: a project root, and a worker's worktree.
  const project = mkdtempSync(join(tmpdir(), "replay-project-")); mkdirSync(join(project, ".git"));
  const gitdir = mkdtempSync(join(tmpdir(), "replay-gitdir-"));
  writeFileSync(join(gitdir, "HEAD"), "ref: refs/heads/pi-subagents/00-replay-0-s0-t0\n");
  const worker = mkdtempSync(join(tmpdir(), "replay-worker-")); writeFileSync(join(worker, ".git"), `gitdir: ${gitdir}\n`);
  let still = 0;
  for (const c of all) {
    const isWorker = /^factory-worker/.test(c.who);
    const input = { ...c.args };
    if (typeof input.command === "string") input.command = input.command.replace(/^cd \S+ && /, "");
    if (typeof input.cwd === "string") input.cwd = project;
    const r = check({ tool: c.tool, input, cwd: isWorker ? worker : project });
    if (r) { still++; console.log(`still refused (${r.rule}): ${c.ts} ${c.who} ${JSON.stringify(input).slice(0, 160)}`); }
  }
  console.log(`replay: ${all.length - still} of ${all.length} recorded refusals now pass${still ? `; ${still} still refused (a fix candidate, or a true block: decide which)` : ""}`);
} else {
  console.error("usage: learn-records.mjs events <project-dir> <out-dir> | replay <out-dir>"); process.exit(2);
}
