#!/usr/bin/env node
// One archived run, for the cockpit's run page (D121): what it was (role,
// model, ticket, times, cost), what the guard refused and whether the guard
// still refuses it today, and what it did, call by call. Read-only, from the
// run archive (archive.sh collect); the same JSON a cloud deployment serves.
//
// Usage: node run-detail.mjs <archive-root> <mission> <run-folder>
//   <run-folder>: the archive folder's name (<run>_<agent>), as the snapshot's
//   timeline gives it (missions[].timeline[].dir).
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { check } from "./guard-rules.mjs";

const SAFE = /^[\w.-]+$/;
const MAX_EVENTS = 400, MAX_TEXT = 600;
const read = (f) => { try { return readFileSync(f, "utf8"); } catch { return null; } };
const textOf = (c) => (typeof c === "string" ? c : Array.isArray(c) ? c.map((x) => (x && (x.text || x.content)) || "").join("") : "");
const cut = (s, n = MAX_TEXT) => { s = String(s ?? ""); return s.length > n ? s.slice(0, n) + "…" : s; };
const when = (r, m) => { const t = r.timestamp ?? r.ts ?? m.timestamp; if (t === undefined) return ""; const d = new Date(typeof t === "number" && t < 1e12 ? t * 1000 : t); return isNaN(d) ? "" : d.toISOString(); };
const ERROR_TEXT = /^\s*(error\b|Error:|fatal:)|exited with code [1-9]|exit code [1-9]|blocked by the factory guard/i;

// The guard's refusal, judged again by today's rules. guard.log keeps the
// input cut at 300 characters (F10): a cut input can't be replayed faithfully.
export function replay(g) {
  let input;
  try { input = JSON.parse(g.input); } catch { return { today: "unknown", why: "the input was cut at 300 characters in guard.log (F10)" }; }
  try {
    const hit = check({ tool: g.tool, input, cwd: g.cwd || process.cwd() });
    return hit ? { today: "refused", rule: hit.rule, why: hit.reason } : { today: "allowed", why: "today's guard lets it through: the refusal was fixed since" };
  } catch (e) { return { today: "unknown", why: `replay failed: ${e.message}` }; }
}

// The transcript, call by call: tool calls with their result's error flag,
// the agent's text, and the guard's refusals in place.
export function events(transcript) {
  const out = [], byId = new Map();
  for (const line of String(transcript || "").split("\n")) {
    if (!line.trim()) continue;
    let r; try { r = JSON.parse(line); } catch { continue; }
    const m = r.message && typeof r.message === "object" ? r.message : {};
    if (r.recordType === "tool_start" || (r.type === "tool" && r.name)) {
      const e = { at: when(r, m), kind: "call", tool: r.toolName || r.name || "?", text: cut(r.argsPreview ?? r.args ?? ""), error: false, result: "" };
      out.push(e); if (r.toolCallId) byId.set(r.toolCallId, e);
      continue;
    }
    if (r.recordType && r.recordType !== "message") continue;
    const role = r.role || m.role;
    if (role === "toolResult" || role === "tool") {
      const text = r.text !== undefined ? String(r.text) : textOf(m.content);
      const error = !!(r.isError || m.isError || ERROR_TEXT.test(text.slice(0, 400)));
      const e = byId.get(r.toolCallId || m.toolCallId);
      const refused = /blocked by the factory guard/i.test(text);
      if (e) { e.error = error; e.result = cut(text, 400); if (refused) e.kind = "refused"; }
      else out.push({ at: when(r, m), kind: refused ? "refused" : "result", tool: r.toolName || m.toolName || "", text: cut(text), error, result: "" });
    } else if (role === "assistant") {
      const text = Array.isArray(m.content) ? m.content.filter((x) => x && x.type === "text").map((x) => x.text).join("\n") : textOf(m.content ?? r.text);
      if (text.trim()) out.push({ at: when(r, m), kind: "text", tool: "", text: cut(text), error: false, result: "" });
    }
  }
  return out;
}

export function runDetail(dir) {
  const j = JSON.parse(read(join(dir, "run.json")) || "null");
  if (!j) return null;
  const end = Date.parse(j.date), start = end - (Number(j.durationMs) || 0);
  const ev = events(read(join(dir, "transcript.jsonl")));
  return {
    contract: 1, run: j.run, dir: dir.split(/[\\/]/).pop(), role: String(j.agent || "?").replace(/^factory-/, ""), agent: j.agent, model: j.model || "", thinking: j.thinking || "",
    ticket: j.ticket || "", briefId: j.briefId || "", head: j.head || "",
    start: isNaN(start) ? "" : new Date(start).toISOString(), end: isNaN(end) ? "" : j.date,
    usage: j.usage || {}, calls: typeof j.calls === "number" ? j.calls : ev.filter((e) => e.kind === "call" || e.kind === "refused").length,
    outcome: j.outcome || {},
    refused: (Array.isArray(j.guard) ? j.guard : []).map((g) => ({ at: g.date || "", rule: g.rule || "", tool: g.tool || "", input: g.input || "", cwd: g.cwd || "", ...replay(g) })),
    errors: ev.filter((e) => e.error).length,
    events: ev.length > MAX_EVENTS ? ev.slice(-MAX_EVENTS) : ev, eventsTotal: ev.length,
    brief: cut(read(join(dir, "brief.md")) || "", 4000), output: cut(read(join(dir, "output.md")) || "", 4000),
    files: j.files || [],
  };
}

// A path with spaces is percent-encoded in import.meta.url: compare URLs.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [root, mission, run] = process.argv.slice(2);
  if (!root || !SAFE.test(mission || "") || !SAFE.test(run || "")) { console.error("usage: run-detail.mjs <archive-root> <mission> <run-folder>"); process.exit(2); }
  const dir = join(root, mission, run);
  const d = existsSync(dir) ? runDetail(dir) : null;
  if (!d) { console.error(`run-detail: no archived run ${mission}/${run}`); process.exit(1); }
  process.stdout.write(JSON.stringify(d) + "\n");
}
