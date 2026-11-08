#!/usr/bin/env node
// Helpers for archive.sh (D97). No dependencies.
//   node archive.mjs collect <out-dir> <mission-dir> <head> [guard.log] [root...]   (meta paths on stdin)
//     root: this checkout's folders (top level, worktrees, git common dir)
//   node archive.mjs list <out-dir>
import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync, statSync, realpathSync } from "node:fs";
import { join, dirname, basename, isAbsolute, resolve } from "node:path";
import { pathToFileURL } from "node:url";

// Redaction is shared with the guard's refusal log (redact.mjs, D101).
import { redact } from "./redact.mjs";
export { redact };

const read = (f) => { try { return readFileSync(f, "utf8"); } catch { return null; } };
const field = (text, name) => (text.match(new RegExp(`^\\*\\*${name}:\\*\\*\\s*(.*)$`, "m")) || [])[1]?.trim() ?? "";

function outcome(missionDir, briefId, ticket) {
  const res = {};
  const vdir = join(missionDir, "verdicts");
  if (briefId && existsSync(vdir)) {
    for (const f of readdirSync(vdir).sort()) {
      const t = read(join(vdir, f));
      if (t && field(t, "Brief") === briefId) { res.verdict = f; res.result = field(t, "Result") || "unknown"; }
    }
  }
  if (ticket) {
    const m = read(join(missionDir, "state", `${ticket}.integrated`));
    if (m) res.integrated = m.trim();
  }
  return res;
}

function thinkingOf(missionDir, agent) {   // runs.tsv (D77): date workflow key agent model thinking
  const t = read(join(missionDir, "runs.tsv"));
  if (!t) return "";
  let th = "";
  for (const l of t.split("\n").slice(1)) { const c = l.split("\t"); if (c[3] === agent && c[5]) th = c[5]; }
  return th;
}

// D101: a run belongs to this checkout when the meta file or a path it holds
// (transcript, execution folder) is under one of the checkout's folders, or
// when its brief id is one the mission recorded (a workflow file, a verdict).
// A run of another clone, another project or another user's mission sharing
// the temp folder is not archived here.
const real = (p) => { try { return realpathSync(p); } catch { return resolve(p); } };
const under = (p, roots) => { const a = [resolve(p), real(p)];
  return roots.some((r) => a.some((x) => x === r || x.startsWith(r.endsWith("/") ? r : r + "/"))); };
// Pi keeps a project's sessions, and pi-subagents its runs' artifacts, under
// ~/.pi/agent/sessions/--<cwd with / as ->--/: the folder name is the working
// directory the run belonged to. One of ours: exactly a root (the project, a
// worktree still listed), or a folder under the git common dir (a worker's
// worktree, removed since).
const piDir = (p) => `--${p.replace(/^[/\\]/, "").replace(/[/\\:]/g, "-")}--`;
function sessionOwned(paths, roots) {
  const exact = new Set(roots.map(piDir));
  const prefixes = roots.filter((r) => /\.git$/.test(r)).map((r) => piDir(r).slice(0, -2) + "-");
  return paths.some((p) => {
    const m = p.match(/\/sessions\/(--[^/]*--)\//);
    return !!m && (exact.has(m[1]) || prefixes.some((x) => m[1].startsWith(x)));
  });
}
function pathsIn(v, out = []) {
  if (typeof v === "string") { if (isAbsolute(v)) out.push(v); }
  else if (Array.isArray(v)) v.forEach((x) => pathsIn(x, out));
  else if (v && typeof v === "object") Object.values(v).forEach((x) => pathsIn(x, out));
  return out;
}
function missionText(dir, acc = []) {     // every text the mission recorded, for brief ids
  let entries = []; try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return acc; }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) missionText(p, acc);
    else if (/\.(md|js|tsv|json|txt)$|\.integrated$|\.pending$/.test(e.name)) { const t = read(p); if (t) acc.push(t); }
  }
  return acc;
}

// Tool calls in a transcript: pi-subagents' tool_start records, else the
// assistant messages' toolCall parts, else bare tool records (older formats).
// A run's start and end, from its transcript's records (ts in ms, or an ISO
// timestamp). pi-subagents' meta has no duration: without this every run
// lasted 0 ms and no refusal fell in its window (found on the gym's records).
export function transcriptSpan(text) {
  let start = Infinity, end = -Infinity;
  for (const line of String(text || "").split("\n")) {
    if (!line) continue;
    const m = line.match(/"ts":\s*(\d{12,})/) || line.match(/"timestamp":\s*"([^"]+)"/);
    if (!m) continue;
    const t = /^\d+$/.test(m[1]) ? Number(m[1]) : Date.parse(m[1]);
    if (Number.isNaN(t)) continue;
    if (t < start) start = t; if (t > end) end = t;
  }
  return start <= end ? { start, end } : null;
}

// The guard's refusals that belong to a run: inside its time window and, when
// the refused command can be read, found in its transcript. Parallel runs in
// the same folder (review axes next to the reviewer) share a window; only the
// one that made the call has it in its transcript.
export function refusalsFor(text, start, end, refusals) {
  return refusals.filter((r) => {
    if (r.t < start - 1000 || r.t > end + 1000) return false;
    // guard.log keeps the input as JSON text, cut at 300 characters (F10):
    // take the command's first characters as the transcript spells them.
    // Both sides are redacted the same way: compare up to the first [REDACTED].
    const head = (x) => { const i = x.indexOf("[REDACTED"); return (i >= 0 ? x.slice(0, i) : x).slice(0, 60); };
    let probe;
    try { const i = JSON.parse(r.input); probe = JSON.stringify(head(String(i.command || i.path || i.task || ""))).slice(1, -1); }
    catch { probe = head(String(r.input || "").replace(/^\{"(command|path|task)":"/, "")).replace(/\\$/, ""); }
    return probe.length < 12 || String(text || "").includes(probe);
  }).map(({ t, ...r }) => r);
}

export function toolCalls(text) {
  const n = (re) => (text.match(re) || []).length;
  return n(/"recordType":\s*"tool_start"/g) || n(/"type":\s*"toolCall"/g) || n(/"type":\s*"tool"[,}]/g);
}

// Imported (tests, other scripts): the helpers only, no command runs.
const isMain = !!process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
const [cmd, ...args] = isMain ? process.argv.slice(2) : ["(imported)"];
if (cmd === "collect") {
  const [out, missionDir, head, guardLog = "", ...rootArgs] = args;
  const roots = [...new Set(rootArgs.filter(Boolean).flatMap((r) => [resolve(r), real(r)]))];
  const recorded = missionText(missionDir).join("\n");
  // The guard's refusals (factory-guard.ts): ISO date, rule, tool, input, cwd.
  const refusals = (read(guardLog) || "").split("\n").filter(Boolean).map((l) => l.split("\t"))
    .map(([date, rule, tool, input, cwd]) => ({ t: Date.parse(date), date, rule, tool, input: redact(input || ""), cwd: cwd || "" }))
    .filter((r) => !Number.isNaN(r.t));
  const metas = readFileSync(0, "utf8").split("\n").filter(Boolean);
  let added = 0, redacted = 0, foreign = 0;
  for (const meta of metas) {
    let j; try { j = JSON.parse(readFileSync(meta, "utf8")); } catch { continue; }
    const base = basename(meta).replace(/_meta\.json$/, "");
    const i = base.indexOf("_");
    const runId = String(j.runId || (i > 0 ? base.slice(0, i) : base));
    const agent = String(j.agent || (i > 0 ? base.slice(i + 1) : "?")).replace(/_\d+$/, "");
    if (!agent.startsWith("factory-")) continue;
    if (roots.length) {
      const input = read(join(dirname(meta), `${basename(meta).replace(/_meta\.json$/, "")}_input.md`)) || "";
      const id = (input.match(/^brief-id:\s*(\S+)/m) || [])[1] || "";
      const ours = under(meta, roots) || pathsIn(j).some((p) => under(p, roots)) || sessionOwned([meta, ...pathsIn(j)], roots)
        || (id.length >= 6 && recorded.includes(id));
      if (!ours) { foreign++; continue; }
    }
    const key = `${runId}_${agent}`.replace(/[^\w.-]/g, "_");
    const dest = join(out, key);
    const known = existsSync(join(dest, "run.json"));   // archived before: add what was missing, refresh the outcome
    mkdirSync(dest, { recursive: true });
    const sib = (suffix) => join(dirname(meta), `${base}${suffix}`);
    const files = { "brief.md": sib("_input.md"), "output.md": sib("_output.md"),
      "transcript.jsonl": existsSync(sib("_transcript.jsonl")) ? sib("_transcript.jsonl") : sib(".jsonl") };
    let brief = read(join(dest, "brief.md")) || "";
    for (const [name, src] of Object.entries(files)) {
      if (existsSync(join(dest, name))) continue;
      const t = read(src); if (t === null) continue;
      const clean = redact(t); if (clean !== t) redacted++;
      writeFileSync(join(dest, name), clean);
      if (name === "brief.md") brief = clean;
    }
    const briefId = (brief.match(/^brief-id:\s*(\S+)/m) || [])[1] || "";
    const ticket = (brief.match(/\bticket\s+(\d{2}[\w-]*)/i) || [])[1] || "";
    const u = j.usage || {};
    const transcript = read(join(dest, "transcript.jsonl")) || "";
    const ts = transcriptSpan(transcript);
    const endMs = ts ? ts.end : statSync(meta).mtimeMs, durationMs = j.durationMs || (ts ? ts.end - ts.start : 0);
    const run = {
      run: runId, agent, model: j.model || "", thinking: j.thinking || thinkingOf(missionDir, agent),
      date: new Date(statSync(meta).mtimeMs).toISOString(), start: new Date(endMs - durationMs).toISOString(), durationMs,
      usage: { input: u.input || 0, output: u.output || 0, cacheRead: u.cacheRead || 0, cacheWrite: u.cacheWrite || 0, cost: u.cost || 0, turns: u.turns || 0 },
      briefId, ticket, head, outcome: outcome(missionDir, briefId, ticket),
      // Refusals inside the run's window that its transcript shows it made.
      guard: refusalsFor(transcript, endMs - durationMs, endMs, refusals),
      calls: toolCalls(transcript),   // D119: the cockpit's timeline never reads transcripts
      files: Object.keys(files).filter((n) => existsSync(join(dest, n))),
    };
    const prev = known ? read(join(dest, "run.json")) : null;
    const first = prev ? JSON.parse(prev) : run;   // when and at which commit it was first seen
    const next = JSON.stringify({ ...run, date: first.date, head: first.head }, null, 2) + "\n";
    if (next !== prev) writeFileSync(join(dest, "run.json"), next);
    if (!known) added++;
  }
  console.log(`archive: ${added} run(s) added to ${out}${redacted ? ` (${redacted} file(s) redacted)` : ""}${foreign ? `; ${foreign} run(s) of another checkout ignored` : ""}`);
} else if (cmd === "refresh") {
  // Runs archived before their times, tool calls or refusals were read from
  // the transcript: fill what's missing from the archived transcript and
  // guard.log. Only runs lacking a field are read.
  const [out, guardLog = ""] = args;
  if (!existsSync(out)) process.exit(0);
  const refusals = (read(guardLog) || "").split("\n").filter(Boolean).map((l) => l.split("\t"))
    .map(([date, rule, tool, input, cwd]) => ({ t: Date.parse(date), date, rule, tool, input: redact(input || ""), cwd: cwd || "" }))
    .filter((r) => !Number.isNaN(r.t));
  let changed = 0;
  for (const d of readdirSync(out).sort()) {
    const f = join(out, d, "run.json"), prev = read(f); if (!prev) continue;
    const j = JSON.parse(prev);
    if (j.start && typeof j.calls === "number" && j.durationMs) continue;
    const transcript = read(join(out, d, "transcript.jsonl")) || "";
    const ts = transcriptSpan(transcript);
    if (ts && !j.durationMs) { j.durationMs = ts.end - ts.start; j.start = new Date(ts.start).toISOString(); j.end = new Date(ts.end).toISOString(); }
    if (!j.start) j.start = new Date(Date.parse(j.date) - (j.durationMs || 0)).toISOString();
    if (typeof j.calls !== "number") j.calls = toolCalls(transcript);
    if (ts && !(j.guard || []).length) j.guard = refusalsFor(transcript, ts.start, ts.end, refusals);
    const next = JSON.stringify(j, null, 2) + "\n";
    if (next !== prev) { writeFileSync(f, next); changed++; }
  }
  console.log(`archive: ${changed} run(s) refreshed in ${out}`);
} else if (cmd === "list") {
  const [out] = args;
  if (!existsSync(out)) process.exit(0);
  for (const d of readdirSync(out).sort()) {
    const r = read(join(out, d, "run.json")); if (!r) continue;
    const j = JSON.parse(r);
    const o = j.outcome || {};
    console.log([j.run, j.agent, j.model, j.ticket || "-", o.result || (o.integrated ? "integrated" : "-"), j.usage?.cost ?? 0, join(out, d), (j.guard || []).length].join("\t"));
  }
} else if (isMain) {
  console.error("usage: archive.mjs collect <out> <mission-dir> <head> | refresh <out> [guard.log] | list <out>"); process.exit(2);
}
