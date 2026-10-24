#!/usr/bin/env node
// metrics.sh --all (D97, P14): one JSON line per mission on stdin → a table
// of every mission and the total, or --json for the cockpit. Cost per MR
// counts the missions that opened one (mr.url, written by mr.sh).
import { readFileSync } from "node:fs";
const rows = readFileSync(0, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const sum = (k) => rows.reduce((a, r) => a + (typeof r[k] === "number" ? r[k] : 0), 0);
const mrs = rows.filter((r) => r.mr);
const total = {
  missions: rows.length, tickets: sum("tickets"), reviewed: sum("reviewed"), firstPass: sum("firstPass"), rounds: sum("rounds"),
  decisions: sum("decisions"), handCommits: sum("handCommits"), runs: sum("runs"), tokensIn: sum("tokensIn"), tokensOut: sum("tokensOut"),
  cost: Math.round(sum("cost") * 100) / 100, scored: sum("scored"), scoreFails: sum("scoreFails"), mrs: mrs.length,
  costPerMr: mrs.length ? Math.round((mrs.reduce((a, r) => a + r.cost, 0) / mrs.length) * 100) / 100 : null,
  decisionsPerMr: mrs.length ? Math.round((mrs.reduce((a, r) => a + (r.decisions || 0) + (r.handCommits || 0), 0) / mrs.length) * 10) / 10 : null,
};
if (process.argv[2] === "--json") { console.log(JSON.stringify({ missions: rows, total }, null, 2)); process.exit(0); }
const pct = (a, b) => (b ? `${Math.round((100 * a) / b)}%` : "-");
const v = (x) => (x === null || x === undefined ? "-" : String(x));
const k = (n) => (n >= 1e6 ? `${(n / 1e6).toFixed(1)}M` : n >= 1e3 ? `${(n / 1e3).toFixed(0)}k` : String(n));
console.log("### Factory metrics: all missions\n");
console.log("| Mission | Intent | Tickets | First pass | Rounds/ticket | Decisions | Hand commits | Cycle | Tokens in/out | Cost | Scored (fail) | MR |");
console.log("|---|---|---|---|---|---|---|---|---|---|---|---|");
for (const r of rows) {
  console.log(`| ${r.mission} | ${v(r.intent)} | ${v(r.tickets)} | ${pct(r.firstPass, r.reviewed)} | ${r.reviewed ? (r.rounds / r.reviewed).toFixed(1) : "-"} | ${v(r.decisions)} | ${v(r.handCommits)} | ${r.cycleHours === null ? "-" : `${r.cycleHours}h`} | ${k(r.tokensIn)}/${k(r.tokensOut)} | ${r.cost} | ${r.scored} (${r.scoreFails}) | ${r.mr ? "yes" : "-"} |`);
}
const t = total;
console.log(`| **Total** (${t.missions}) | | ${t.tickets} | ${pct(t.firstPass, t.reviewed)} | ${t.reviewed ? (t.rounds / t.reviewed).toFixed(1) : "-"} | ${t.decisions} | ${t.handCommits} | | ${k(t.tokensIn)}/${k(t.tokensOut)} | ${t.cost} | ${t.scored} (${t.scoreFails}) | ${t.mrs} |`);
console.log(`\nCost per MR: ${v(t.costPerMr)} · human interventions (decisions + hand commits) per MR: ${v(t.decisionsPerMr)}`);
