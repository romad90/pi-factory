#!/usr/bin/env node
// Checks that every factory subagent runs on its own configured model, and
// that judges never share a model family with what they judge (D31).
// pi-subagents now takes exactly one model per agent: the `fallbackModels`
// frontmatter field was removed upstream and makes the agent fail to launch.
//
// Usage: node scripts/factory/models-lint.mjs
// Inputs: the factory agents (.pi/agents/factory, or the installed package's)
//         with their effective model: frontmatter, then user and project
//         agentOverrides (D92); subagents settings, user then project (builtins
//         off, model scope); .factory/model-families.json
import { readFileSync, existsSync } from "node:fs";
import { effectiveAgents, subagentSettings, agentsDir, userSettingsFile } from "./effective-models.mjs";

const SETTINGS = ".pi/settings.json";
const FAMILIES = ".factory/model-families.json";

let failed = false;
const ok = (m) => console.log(`  ✓ ${m}`);
const bad = (m) => { console.log(`  ✗ ${m}`); failed = true; };
const warn = (m) => console.log(`  ! ${m}`);
const isPlaceholder = (v) => typeof v === "string" && /[<>]/.test(v);
const glob = (pattern) =>
  new RegExp("^" + pattern.split("*").map((s) => s.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*") + "$", "i");

console.log("Factory models");
if (!existsSync(SETTINGS) && !existsSync(userSettingsFile())) bad(`missing ${SETTINGS} (and no user settings)`);
if (!existsSync(FAMILIES)) bad(`missing ${FAMILIES}`);
if (failed) process.exit(1);

const sub = subagentSettings().merged;
// D92: in CI, a project on the installed package has no models in the repo:
// they are set per machine and checked by each machine's pre-flight.
if (process.argv.includes("--per-machine-ok") && !existsSync(".pi/agents/factory")
    && effectiveAgents().every((a) => !a.model || isPlaceholder(a.model))) {
  ok("models are set per machine (factory installed as a package): checked by the pre-flight, not here");
  console.log("MODELS: PASS");
  process.exit(0);
}
const fam = JSON.parse(readFileSync(FAMILIES, "utf8"));

// Package-level guards
sub.disableBuiltins === true
  ? ok("builtin agents disabled (only factory agents, all fresh)")
  : bad("subagents.disableBuiltins must be true (builtin worker/oracle default to forked context)");
const scope = sub.modelScope ?? {};
const allow = Array.isArray(scope.allow) ? scope.allow : [];
if (scope.enforce === true && allow.length && !allow.some(isPlaceholder)) ok(`model scope enforced (${allow.join(", ")})`);
else bad("subagents.modelScope must have enforce: true and a filled allow list");

// Agents
const agents = effectiveAgents();
if (!agents.length) bad(`no factory agents in ${agentsDir()}`);
const models = {};                                   // agent → [primary, ...fallbacks]
for (const { file, fm, model, source } of agents) {
  const name = fm.name;
  if (!name) { bad(`${file}: no name`); continue; }
  if (fm.defaultContext !== "fresh") bad(`${name}: defaultContext must be fresh`);
  if (fm.inheritSkills !== "false") bad(`${name}: inheritSkills must be false (pinned skills only)`);
  if (!fm.skillPath) bad(`${name}: skillPath must point at the pinned skills`);
  if ("memory" in fm) bad(`${name}: agent memory is off for factory agents (could carry instrument details past the wall)`);
  if (!model) { bad(`${name}: no model (frontmatter or agentOverrides.${name}.model)`); continue; }
  if ("fallbackModels" in fm) bad(`${name}: fallbackModels was removed by pi-subagents and stops the agent from launching; delete that line`);
  const list = [model];
  if (list.some(isPlaceholder)) { bad(`${name}: placeholder model ids left (${list.join(", ")}); set them per machine: factory models apply --user`); continue; }
  if (source === "user" || source === "project") ok(`${name}: ${model} (from ${source} agentOverrides)`);
  models[name] = list;
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
