#!/usr/bin/env node
// Checks that every factory subagent runs on its own configured model, and
// that judges never share a model family with what they judge (D31).
// pi-subagents now takes exactly one model per agent: the `fallbackModels`
// frontmatter field was removed upstream and makes the agent fail to launch.
//
// Usage: node scripts/factory/models-lint.mjs
// Inputs: .pi/agents/factory/*.md (model, fallbackModels in frontmatter),
//         .pi/settings.json (builtins off, model scope), .factory/model-families.json
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";

const SETTINGS = ".pi/settings.json";
const FAMILIES = ".factory/model-families.json";
const AGENTS_DIR = ".pi/agents/factory";

let failed = false;
const ok = (m) => console.log(`  ✓ ${m}`);
const bad = (m) => { console.log(`  ✗ ${m}`); failed = true; };
const warn = (m) => console.log(`  ! ${m}`);
const isPlaceholder = (v) => typeof v === "string" && /[<>]/.test(v);
const glob = (pattern) =>
  new RegExp("^" + pattern.split("*").map((s) => s.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*") + "$", "i");

function frontmatter(file) {
  const text = readFileSync(file, "utf8");
  const m = text.match(/^---\n([\s\S]*?)\n---/);
  const out = {};
  if (!m) return out;
  for (const line of m[1].split("\n")) {
    const kv = line.match(/^([A-Za-z][\w-]*):\s*(.*)$/);
    if (kv) out[kv[1]] = kv[2].trim();
  }
  return out;
}

console.log("Factory models");
for (const f of [SETTINGS, FAMILIES]) if (!existsSync(f)) { bad(`missing ${f}`); }
if (failed) process.exit(1);

const sub = JSON.parse(readFileSync(SETTINGS, "utf8")).subagents ?? {};
const fam = JSON.parse(readFileSync(FAMILIES, "utf8"));
const overrides = sub.agentOverrides ?? {};

// Package-level guards
sub.disableBuiltins === true
  ? ok("builtin agents disabled (only factory agents, all fresh)")
  : bad("subagents.disableBuiltins must be true (builtin worker/oracle default to forked context)");
const scope = sub.modelScope ?? {};
const allow = Array.isArray(scope.allow) ? scope.allow : [];
if (scope.enforce === true && allow.length && !allow.some(isPlaceholder)) ok(`model scope enforced (${allow.join(", ")})`);
else bad("subagents.modelScope must have enforce: true and a filled allow list");

// Agents
const agents = readdirSync(AGENTS_DIR).filter((f) => f.endsWith(".md")).map((f) => ({ file: join(AGENTS_DIR, f), fm: frontmatter(join(AGENTS_DIR, f)) }));
const models = {};                                   // agent → [primary, ...fallbacks]
for (const { file, fm } of agents) {
  const name = fm.name;
  if (!name) { bad(`${file}: no name`); continue; }
  if (fm.defaultContext !== "fresh") bad(`${name}: defaultContext must be fresh`);
  if (fm.inheritSkills !== "false") bad(`${name}: inheritSkills must be false (pinned skills only)`);
  if (!fm.skillPath) bad(`${name}: skillPath must point at the pinned skills`);
  if ("memory" in fm) bad(`${name}: agent memory is off for factory agents (could carry instrument details past the wall)`);
  if (!fm.model) { bad(`${name}: no model in its frontmatter (run node scripts/factory/migrate-models.mjs)`); continue; }
  if ("fallbackModels" in fm) bad(`${name}: fallbackModels was removed by pi-subagents and stops the agent from launching; delete that line`);
  const list = [fm.model];
  if (list.some(isPlaceholder)) { bad(`${name}: placeholder model ids left (${list.join(", ")})`); continue; }
  models[name] = list;
}
for (const name of Object.keys(overrides)) {
  if (name.startsWith("factory-")) bad(`agentOverrides.${name}: pi-subagents only accepts builtin names there and fails to load agents; run node scripts/factory/migrate-models.mjs`);
}

// Scope and families
const familyOf = (id) => fam.families.find((f) => glob(f.match).test(id))?.family;
for (const [name, list] of Object.entries(models)) {
  for (const id of list) {
    if (allow.length && !allow.some((p) => glob(p).test(id))) bad(`${name}: ${id} is outside the model scope`);
    if (!familyOf(id)) bad(`${name}: ${id} matches no family in ${FAMILIES}; add one`);
  }
}
for (const [left, right] of fam.rules) {
  const fams = (group) => new Set(group.flatMap((a) => (models[a] ?? []).map(familyOf)).filter(Boolean));
  const L = fams(left), R = fams(right);
  const shared = [...L].filter((x) => R.has(x));
  if (!left.concat(right).every((a) => models[a])) continue;   // already reported above
  shared.length
    ? bad(`${left.join("/")} share family ${shared.join(", ")} with ${right.join("/")} `)
    : ok(`${left.join("/")} [${[...L].join(", ")}] ≠ ${right.join("/")} [${[...R].join(", ")}]`);
}

console.log(failed ? "MODELS: FAIL" : "MODELS: PASS");
process.exit(failed ? 1 : 0);
