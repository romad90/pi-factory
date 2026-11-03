#!/usr/bin/env node
// Where agents fought their setup (P23): read from the archived transcripts,
// never from what an agent says about itself. A self-report is a judge; the
// transcript is the evidence.
//
// Usage: node frictions.mjs <archive-dir-of-a-mission> [--top N] [--json]
//   (scripts/factory/archive.sh frictions <mission> collects first, then calls this)
//
// Three signals per run, each countable without a model:
//   failed     a tool call whose result is an error: the record's isError flag,
//              or text that only an error starts with (a non-zero exit, a guard
//              refusal, a supervisor timeout)
//   repeated   the same call (tool + arguments) three times or more in one run:
//              an agent going in circles
//   refused    the command guard's refusals listed in run.json
// Calls are grouped across runs by a signature (tool + arguments, digits
// folded), so "port 3001 in use" and "port 3002 in use" count as one cause.
// A signature seen in several runs is a paper cut for the factory to fix: a
// brief line, a setup step, a skill.
import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";

const argv = process.argv.slice(2);
const opt = (name, dflt) => { const i = argv.indexOf(name); return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt; };
const dir = argv.find((a, i) => !a.startsWith("--") && argv[i - 1] !== "--top");
const top = Number(opt("--top", 10)) || 10;
if (!dir || !existsSync(dir)) { console.error(`frictions: no archive at ${dir || "(none)"} (run archive.sh collect <mission> first)`); process.exit(2); }

const ERROR_TEXT = /^\s*(error\b|Error:|fatal:)|exited with code [1-9]|exit code [1-9]|blocked by the factory guard|Timed out waiting for supervisor|command not found|No such file or directory|EADDRINUSE|ENOENT|EACCES/i;
const sig = (tool, args) => `${tool} ${String(args || "").replace(/\s+/g, " ").replace(/\d+/g, "#").trim()}`.slice(0, 100);
const readJson = (f) => { try { return JSON.parse(readFileSync(f, "utf8")); } catch { return null; } };
const textOf = (c) => (typeof c === "string" ? c : Array.isArray(c) ? c.map((x) => (x && (x.text || x.content)) || "").join("") : "");

const runs = [], bySig = new Map();
const note = (kind, s, run, agent, sample) => {
  const e = bySig.get(`${kind}\t${s}`) || { kind, sig: s, n: 0, runs: new Set(), agents: new Set(), sample: "" };
  e.n++; e.runs.add(run); e.agents.add(agent); if (!e.sample && sample) e.sample = sample.replace(/\s+/g, " ").slice(0, 120);
  bySig.set(`${kind}\t${s}`, e);
};

for (const name of readdirSync(dir).sort()) {
  const rd = join(dir, name);
  if (!statSync(rd).isDirectory()) continue;
  const meta = readJson(join(rd, "run.json")) || {};
  const run = meta.run || name, agent = meta.agent || "?";
  const calls = new Map(), seen = new Map();
  let failed = 0, repeated = 0, total = 0;
  const tf = join(rd, "transcript.jsonl");
  if (existsSync(tf)) {
    for (const line of readFileSync(tf, "utf8").split("\n")) {
      if (!line.trim()) continue;
      let r; try { r = JSON.parse(line); } catch { continue; }
      if (r.recordType === "tool_start" && r.toolCallId) {
        const s = sig(r.toolName || "?", r.argsPreview);
        calls.set(r.toolCallId, s); total++;
        seen.set(s, (seen.get(s) || 0) + 1);
        continue;
      }
      if (r.recordType && r.recordType !== "message") continue;
      const m = r.message && typeof r.message === "object" ? r.message : {};
      const role = r.role || m.role;
      if (role !== "toolResult" && role !== "tool") continue;
      const id = r.toolCallId || m.toolCallId;
      const text = r.text !== undefined ? String(r.text) : textOf(m.content);
      if (r.isError || m.isError || ERROR_TEXT.test(text.slice(0, 400))) {
        failed++;
        note("failed", calls.get(id) || sig(r.toolName || m.toolName || "?", ""), run, agent, text);
      }
    }
  }
  for (const [s, n] of seen) if (n >= 3) { repeated++; note("repeated", s, run, agent, `${n} times in one run`); }
  const refused = Array.isArray(meta.guard) ? meta.guard : [];
  for (const g of refused) note("refused", `${g.rule || "?"} ${String(g.input || g.command || "").replace(/\d+/g, "#")}`.slice(0, 100), run, agent, g.reason || "");
  runs.push({ run, agent, ticket: meta.ticket || "", calls: total, failed, repeated, refused: refused.length });
}

const groups = [...bySig.values()].sort((a, b) => b.runs.size - a.runs.size || b.n - a.n);
if (argv.includes("--json")) {
  console.log(JSON.stringify({ runs, frictions: groups.slice(0, top).map((g) => ({ ...g, runs: g.runs.size, agents: [...g.agents] })) }, null, 2));
  process.exit(0);
}
if (!runs.length) { console.log("frictions: no archived runs yet"); process.exit(0); }
const totals = runs.reduce((a, r) => ({ calls: a.calls + r.calls, failed: a.failed + r.failed, refused: a.refused + r.refused }), { calls: 0, failed: 0, refused: 0 });
console.log(`Frictions (${runs.length} runs, ${totals.calls} tool calls: ${totals.failed} failed, ${totals.refused} refused by the guard)`);
console.log(["run".padEnd(10), "agent".padEnd(22), "ticket".padEnd(6), "calls".padStart(5), "failed".padStart(6), "loops".padStart(5), "refused".padStart(7)].join(" "));
for (const r of runs)
  console.log([r.run.slice(0, 10).padEnd(10), r.agent.slice(0, 22).padEnd(22), r.ticket.slice(0, 2).padEnd(6), String(r.calls).padStart(5),
    String(r.failed).padStart(6), String(r.repeated).padStart(5), String(r.refused).padStart(7)].join(" "));
if (groups.length) {
  console.log(`\nRecurring causes, most runs first (a cause in several runs is a paper cut to fix in a brief, a setup step or a skill)`);
  for (const g of groups.slice(0, top))
    console.log(`  ${g.kind.padEnd(8)} ${String(g.runs.size).padStart(2)} run(s) ${String(g.n).padStart(3)}×  ${g.sig}${g.sample ? `\n           e.g. ${g.sample}` : ""}`);
}
