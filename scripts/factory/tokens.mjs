#!/usr/bin/env node
// Where a mission's tokens go (P20, token budget): per run, the size of each
// request the agent sent, the largest one, and the tool results that filled
// it. An agent resends its whole conversation every turn, so a provider's
// per-request or per-window token limit is hit by what accumulates: files
// read, test and lint logs, subagent reports. This names them.
//
// Usage: node tokens.mjs <archive-dir-of-a-mission> [--budget N] [--top N] [--json | --shape]
//   (scripts/factory/archive.sh tokens <mission> collects first, then calls this)
//
// Reads each run's run.json and transcript.jsonl (pi-subagents' child
// transcript: assistant messages carry usage; toolResult messages carry the
// tool's output, bounded at 32 KB per result in the transcript).
// Request size of a turn = input + cacheRead + cacheWrite of that assistant
// message (what the provider counted). "Next" = the request the run would have
// sent after its last tool results: last request + last output + those results
// (estimated at 4 characters a token). A run stopped by a size limit (429 with
// the window's quota untouched) shows it there.
import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";

const argv = process.argv.slice(2);
const opt = (name, dflt) => { const i = argv.indexOf(name); return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt; };
const dir = argv.find((a, i) => !a.startsWith("--") && !["--budget", "--top"].includes(argv[i - 1]));
const budget = Number(opt("--budget", process.env.FACTORY_CONTEXT_BUDGET || 0)) || 0;
const top = Number(opt("--top", 10)) || 10;
const asJson = argv.includes("--json");
if (!dir || !existsSync(dir)) { console.error(`tokens: no archive at ${dir || "(none)"} (run archive.sh collect <mission> first)`); process.exit(2); }

// --shape: the kinds of records in the transcripts, their field names and
// usage numbers, never their text: what to look at when a Pi or pi-subagents
// update changes the format and the table comes out empty.
if (argv.includes("--shape")) {
  const kinds = {};
  for (const name of readdirSync(dir).sort()) {
    const tf = join(dir, name, "transcript.jsonl");
    if (!existsSync(tf)) continue;
    for (const line of readFileSync(tf, "utf8").split("\n")) {
      let r; try { r = JSON.parse(line); } catch { continue; }
      const m = r.message && typeof r.message === "object" ? r.message : {};
      const key = [r.recordType, r.type, r.role, m.role].map((x) => x || "-").join(" | ");
      const k = (kinds[key] ??= { n: 0, fields: new Set(), message: new Set(), usage: null });
      k.n++; Object.keys(r).forEach((f) => k.fields.add(f)); Object.keys(m).forEach((f) => k.message.add(f));
      const u = r.usage || m.usage;
      if (u && !k.usage) k.usage = JSON.stringify(u).slice(0, 200);
    }
  }
  for (const [key, k] of Object.entries(kinds))
    console.log(`${key}  ×${k.n}\n  fields: ${[...k.fields].join(", ")}${k.message.size ? `\n  message: ${[...k.message].join(", ")}` : ""}${k.usage ? `\n  usage: ${k.usage}` : ""}`);
  process.exit(0);
}

// Usage field names differ across Pi, pi-subagents and providers.
const num = (u, ...keys) => { for (const key of keys) if (u && Number.isFinite(u[key])) return u[key]; return 0; };
function requestSize(u) {
  if (!u || typeof u !== "object") return 0;
  const parts = num(u, "input", "inputTokens", "input_tokens", "prompt_tokens")
    + num(u, "cacheRead", "cacheReadTokens", "cache_read_input_tokens")
    + num(u, "cacheWrite", "cacheWriteTokens", "cache_creation_input_tokens");
  return parts || Math.max(0, num(u, "totalTokens", "total_tokens") - num(u, "output", "outputTokens", "output_tokens", "completion_tokens"));
}
const est = (s) => Math.ceil(String(s || "").length / 4);
const k = (n) => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(n));
const readJson = (f) => { try { return JSON.parse(readFileSync(f, "utf8")); } catch { return null; } };

const runs = [];
for (const name of readdirSync(dir).sort()) {
  const rd = join(dir, name);
  if (!statSync(rd).isDirectory()) continue;
  const meta = readJson(join(rd, "run.json")) || {};
  const tf = join(rd, "transcript.jsonl");
  const turns = [], results = [], calls = new Map();
  let since = 0, lastReq = 0, lastOut = 0, error = "";
  if (existsSync(tf)) {
    for (const line of readFileSync(tf, "utf8").split("\n")) {
      if (!line.trim()) continue;
      let r; try { r = JSON.parse(line); } catch { continue; }
      if (r.recordType === "tool_start" && r.toolCallId) calls.set(r.toolCallId, r.argsPreview || "");
      if (r.recordType && r.recordType !== "message") continue;
      const m = r.message && typeof r.message === "object" ? r.message : {};
      const role = r.role || m.role;
      if (role === "assistant") {
        const err = r.errorMessage || m.errorMessage;
        if (err) error = String(err).slice(0, 160);
        const req = requestSize(r.usage || m.usage);
        if (req) {
          lastReq = req; lastOut = num(r.usage || m.usage, "output", "outputTokens", "output_tokens"); since = 0;
          turns.push(lastReq);
        }
      } else if (role === "toolResult" || role === "tool") {
        if (r.text === undefined && Array.isArray(m.content)) r.text = m.content.map((c) => (c && c.text) || "").join("");
        if (!r.toolName && m.toolName) r.toolName = m.toolName;
        if (!r.toolCallId && m.toolCallId) r.toolCallId = m.toolCallId;
        const t = est(r.text);
        since += t;
        results.push({ tokens: t, tool: r.toolName || "?", args: String(calls.get(r.toolCallId) || "").replace(/\s+/g, " ").slice(0, 90), truncated: !!r.outputTruncated });
      }
    }
  }
  const peak = turns.length ? Math.max(...turns) : 0;
  const next = turns.length && since ? lastReq + lastOut + since : 0;
  runs.push({ run: meta.run || name, agent: meta.agent || "?", model: meta.model || "", ticket: meta.ticket || "",
    turns: turns.length, peak, next, error, results, toolTokens: results.reduce((a, b) => a + b.tokens, 0) });
}

if (asJson) { console.log(JSON.stringify({ budget, runs: runs.map(({ results, ...r }) => ({ ...r, largest: results.sort((a, b) => b.tokens - a.tokens).slice(0, top) })) }, null, 2)); process.exit(0); }

if (!runs.length) { console.log("tokens: no archived runs yet"); process.exit(0); }
const over = (n) => (budget && n > budget ? " OVER" : "");
console.log(`Tokens per request (${runs.length} runs${budget ? `, budget ${k(budget)}` : ""})`);
console.log(["run".padEnd(10), "agent".padEnd(22), "ticket".padEnd(6), "turns".padStart(5), "peak".padStart(8), "next*".padStart(8), " tool results"].join(" "));
for (const r of runs) {
  console.log([r.run.slice(0, 10).padEnd(10), r.agent.slice(0, 22).padEnd(22), r.ticket.slice(0, 2).padEnd(6), String(r.turns).padStart(5),
    (k(r.peak) + over(r.peak)).padStart(8), (r.next ? k(r.next) + over(r.next) : "-").padStart(8), " " + k(r.toolTokens)].join(" ")
    + (r.error ? `  ! ${r.error}` : ""));
}
console.log("* next: the request after the run's last tool results (last request + its output + those results), the one a size limit refuses.");

const all = runs.flatMap((r) => r.results.map((x) => ({ ...x, agent: r.agent, ticket: r.ticket })));
const total = all.reduce((a, b) => a + b.tokens, 0);
if (total) {
  console.log(`\nLargest tool results (estimated at 4 characters a token; each is resent on every later turn)`);
  for (const x of [...all].sort((a, b) => b.tokens - a.tokens).slice(0, top))
    console.log(`  ${k(x.tokens).padStart(6)}  ${x.agent.slice(0, 22).padEnd(22)} ${x.tool.padEnd(8)} ${x.args}${x.truncated ? "  (cut at 32 KB in the transcript: larger in the request)" : ""}`);
  const byTool = {};
  for (const x of all) byTool[x.tool] = (byTool[x.tool] || 0) + x.tokens;
  console.log(`\nBy tool: ${Object.entries(byTool).sort((a, b) => b[1] - a[1]).map(([t, n]) => `${t} ${Math.round((100 * n) / total)}%`).join(", ")}`);
  const byAgent = {};
  for (const r of runs) byAgent[r.agent] = Math.max(byAgent[r.agent] || 0, r.peak, r.next);
  console.log(`Largest request per agent: ${Object.entries(byAgent).sort((a, b) => b[1] - a[1]).map(([a, n]) => `${a.replace(/^factory-/, "")} ${k(n)}${over(n)}`).join(", ")}`);
}
