#!/usr/bin/env node
// The architect's strategy, checked and turned into missions (P22).
//
// Usage: node strategy.mjs check  <job-dir> <scratch-dir>
//        node strategy.mjs create <job-dir> <scratch-dir> <job> <approved line>
//        node strategy.mjs list   <job-dir>        (TSV: name, intent, after)
//
// check:  what docs/agents/strategy-format.md requires; one problem per line,
//         exit 1 when there is any. The architect's brief reads them back.
// create: a spec.md per mission, in a folder of its own, from the mission's
//         fields and text: the mission starts at the contract, no grilling.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const [cmd, jobDir, scratch, job, approved] = process.argv.slice(2);
const read = (f) => { try { return readFileSync(f, "utf8"); } catch { return ""; } };
const s = read(join(jobDir, "strategy.md")), measures = read(join(jobDir, "measures.md"));
const INTENTS = ["maintenance", "refactor", "feature", "bugfix"];
const field = (t, name) => ((t.match(new RegExp(`^\\*\\*${name}:\\*\\*\\s*(.*)$`, "m")) || [])[1] || "").trim();
const section = (t, h) => { const m = t.split(new RegExp(`^## ${h}\\b.*$`, "m")); return m.length > 1 ? m[1].split(/^## /m)[0] : ""; };
const cites = (t) => [...t.matchAll(/\[(M-\d+)\]/g)].map((m) => m[1]);
const list = (v) => (!v || v === "-" ? [] : v.split(",").map((x) => x.trim()).filter(Boolean));

function missions() {
  return section(s, "Missions").split(/^### /m).slice(1).map((b) => {
    const head = b.split("\n")[0].trim(), name = head.replace(/^\d+\.\s*/, "");
    const text = b.split("\n").slice(1).filter((l) => !/^\*\*[A-Z][\w ]*:\*\*/.test(l)).join("\n").trim();
    return { name, intent: field(b, "Intent"), after: field(b, "After") || "-", max: field(b, "Max tickets"), scope: field(b, "Scope"),
      done: field(b, "Done when"), frozenPaths: list(field(b, "Frozen paths")), frozenTests: list(field(b, "Frozen tests")), text };
  });
}

function check() {
  const p = [];
  if (!s) return ["no strategy.md"];
  const known = new Set([...measures.matchAll(/^\| (M-\d+) \|/gm)].map((m) => m[1]));
  for (const c of new Set(cites(s))) if (!known.has(c)) p.push(`[${c}] is cited but measures.md has no such row`);
  const opts = section(s, "Options").split(/^### /m).slice(1).map((b) => ({ letter: b.trim()[0], body: b }));
  if (opts.length < 2) p.push(`## Options has ${opts.length} option(s): compare at least two`);
  for (const o of opts) {
    if (!field(o.body, "Value")) p.push(`option ${o.letter}: no **Value:** line`);
    else if (!cites(field(o.body, "Value")).length) p.push(`option ${o.letter}: its value cites no measurement`);
    if (!field(o.body, "Cost")) p.push(`option ${o.letter}: no **Cost:** line`);
    if (!field(o.body, "Leaves out")) p.push(`option ${o.letter}: no **Leaves out:** line`);
  }
  const chosen = field(section(s, "Choice"), "Chosen").replace(/[^A-Z].*$/, "");
  if (!chosen) p.push("## Choice has no **Chosen:** line");
  else if (!opts.some((o) => o.letter === chosen)) p.push(`**Chosen:** ${chosen} is not one of the options`);
  if (!cites(section(s, "Choice")).length) p.push("## Choice cites no measurement: say why from the numbers");
  if (!cites(section(s, "What the measurements say")).length) p.push("## What the measurements say cites no measurement");
  const ms = missions();
  if (!ms.length) p.push("## Missions lists no mission");
  if (ms.length > 4) p.push(`${ms.length} missions: at most 4 per job (a larger job is two jobs)`);
  const seen = [];
  for (const m of ms) {
    const at = `mission ${m.name || "?"}`;
    if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(m.name)) p.push(`${at}: the name must be lowercase words and dashes`);
    else if (existsSync(join(scratch, m.name, "spec.md")) && !read(join(scratch, m.name, "spec.md")).includes(`**Job:** ${job || ""}`.trim()))
      p.push(`${at}: a mission with this name already exists`);
    if (!INTENTS.includes(m.intent)) p.push(`${at}: **Intent:** must be one of ${INTENTS.join(", ")}`);
    if (!/`[^`]+`/.test(m.done)) p.push(`${at}: **Done when:** needs a command in backticks`);
    if (!/^\d+$/.test(m.max)) p.push(`${at}: **Max tickets:** must be a number`);
    if (m.after !== "-" && !seen.includes(m.after)) p.push(`${at}: **After:** ${m.after} is not an earlier mission`);
    if (m.intent === "refactor" && !m.frozenTests.length) p.push(`${at}: a refactor names its **Frozen tests:**`);
    if (!m.text) p.push(`${at}: no mission text under its fields`);
    seen.push(m.name);
  }
  if (!/^## Decisions for the team/m.test(s)) p.push("no ## Decisions for the team section (write \"- none\" if there is none)");
  return p;
}

if (cmd === "check") {
  const p = check();
  if (p.length) { console.log(p.map((x) => `- ${x}`).join("\n")); process.exit(1); }
  console.log("strategy: OK");
} else if (cmd === "list") {
  for (const m of missions()) console.log([m.name, m.intent, m.after].join("\t"));
} else if (cmd === "create") {
  const p = check(); if (p.length) { console.error(p.join("\n")); process.exit(1); }
  for (const m of missions()) {
    const d = join(scratch, m.name); mkdirSync(d, { recursive: true });
    const f = join(d, "spec.md");
    if (existsSync(f)) { console.log(`  ${m.name}: spec exists, kept`); continue; }
    const L = [`# ${m.name}`, "", `**Intent:** ${m.intent}`, `**Job:** ${job} (${approved})`, `**After:** ${m.after}`, `**Max tickets:** ${m.max}`, "",
      "## Problem", "", m.text, "", "## Scope", "", m.scope || "-", "", "## Done when", "", m.done, ""];
    if (m.frozenPaths.length) L.push("## Frozen paths", "", ...m.frozenPaths.map((x) => `- ${x}`), "");
    if (m.frozenTests.length) L.push("## Frozen tests", "", ...m.frozenTests.map((x) => `- ${x}`), "");
    L.push(`Written from .scratch/${job}/strategy.md, approved by a person. It settles the scope: no grilling; what it leaves open goes to the contract critic.`);
    writeFileSync(f, L.join("\n") + "\n");
    console.log(`  ${m.name}: ${m.intent}${m.after !== "-" ? `, after ${m.after}` : ""}`);
  }
} else { console.error("usage: strategy.mjs check|create|list <job-dir> ..."); process.exit(2); }
