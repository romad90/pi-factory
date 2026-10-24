#!/usr/bin/env node
// Helpers for archive.sh (D97). No dependencies.
//   node archive.mjs collect <out-dir> <mission-dir> <head> [guard.log]   (meta paths on stdin)
//   node archive.mjs list <out-dir>
import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync, statSync } from "node:fs";
import { join, dirname, basename } from "node:path";

// The patch guard's secret patterns (patch-guard.sh, "secrets"), applied to
// whole text instead of added lines.
export const SECRET = new RegExp([
  "-----BEGIN ([A-Z]+ )?PRIVATE KEY-----[\\s\\S]*?-----END ([A-Z]+ )?PRIVATE KEY-----",
  "-----BEGIN ([A-Z]+ )?PRIVATE KEY-----",
  "AKIA[0-9A-Z]{16}",
  "gh[pousr]_[A-Za-z0-9]{36}",
  "glpat-[A-Za-z0-9_-]{20}",
  "xox[baprs]-[A-Za-z0-9-]{10,}",
  "sk-[A-Za-z0-9]{32,}",
  "(password|passwd|secret|api_?key|token)[\"']?\\s*[:=]\\s*[\"'][^\"'$<{ ]{8,}[\"']",
].join("|"), "gi");
export const redact = (s) => s.replace(SECRET, "[REDACTED]");

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

const [cmd, ...args] = process.argv.slice(2);
if (cmd === "collect") {
  const [out, missionDir, head, guardLog = ""] = args;
  // The guard's refusals (factory-guard.ts): ISO date, rule, tool, input, cwd.
  const refusals = (read(guardLog) || "").split("\n").filter(Boolean).map((l) => l.split("\t"))
    .map(([date, rule, tool, input, cwd]) => ({ t: Date.parse(date), date, rule, tool, input: redact(input || ""), cwd: cwd || "" }))
    .filter((r) => !Number.isNaN(r.t));
  const metas = readFileSync(0, "utf8").split("\n").filter(Boolean);
  let added = 0, redacted = 0;
  for (const meta of metas) {
    let j; try { j = JSON.parse(readFileSync(meta, "utf8")); } catch { continue; }
    const base = basename(meta).replace(/_meta\.json$/, "");
    const i = base.indexOf("_");
    const runId = String(j.runId || (i > 0 ? base.slice(0, i) : base));
    const agent = String(j.agent || (i > 0 ? base.slice(i + 1) : "?")).replace(/_\d+$/, "");
    if (!agent.startsWith("factory-")) continue;
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
    const run = {
      run: runId, agent, model: j.model || "", thinking: j.thinking || thinkingOf(missionDir, agent),
      date: new Date(statSync(meta).mtimeMs).toISOString(), durationMs: j.durationMs || 0,
      usage: { input: u.input || 0, output: u.output || 0, cacheRead: u.cacheRead || 0, cacheWrite: u.cacheWrite || 0, cost: u.cost || 0, turns: u.turns || 0 },
      briefId, ticket, head, outcome: outcome(missionDir, briefId, ticket),
      // Refusals inside the run's time window (end = meta's time, start = end - duration).
      guard: (() => { const end = statSync(meta).mtimeMs, start = end - (j.durationMs || 0) - 1000;
        return refusals.filter((r) => r.t >= start && r.t <= end + 1000).map(({ t, ...r }) => r); })(),
      files: Object.keys(files).filter((n) => existsSync(join(dest, n))),
    };
    const prev = known ? read(join(dest, "run.json")) : null;
    const first = prev ? JSON.parse(prev) : run;   // when and at which commit it was first seen
    const next = JSON.stringify({ ...run, date: first.date, head: first.head }, null, 2) + "\n";
    if (next !== prev) writeFileSync(join(dest, "run.json"), next);
    if (!known) added++;
  }
  console.log(`archive: ${added} run(s) added to ${out}${redacted ? ` (${redacted} file(s) redacted)` : ""}`);
} else if (cmd === "list") {
  const [out] = args;
  if (!existsSync(out)) process.exit(0);
  for (const d of readdirSync(out).sort()) {
    const r = read(join(out, d, "run.json")); if (!r) continue;
    const j = JSON.parse(r);
    const o = j.outcome || {};
    console.log([j.run, j.agent, j.model, j.ticket || "-", o.result || (o.integrated ? "integrated" : "-"), j.usage?.cost ?? 0, join(out, d), (j.guard || []).length].join("\t"));
  }
} else {
  console.error("usage: archive.mjs collect <out> <mission-dir> <head> | list <out>"); process.exit(2);
}
