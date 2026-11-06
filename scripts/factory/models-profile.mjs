#!/usr/bin/env node
// Per-machine models profile: configure the factory's models once, reuse them
// in every repo. The profile lives outside any repo (model ids and providers
// are yours, not the template's), by default ~/.pi-factory/models.json.
//
// Usage (from a target repo root):
//   node scripts/factory/models-profile.mjs capture [profile]   # save this repo's configured models
//   node scripts/factory/models-profile.mjs apply   [profile]   # write them into this repo
//   node scripts/factory/models-profile.mjs apply --user [profile]
//        # write them into this machine's Pi settings as agentOverrides (D92):
//        # every repo on this machine, copied or on the package, uses them, and
//        # a git pull can't bring another machine's models
// install-into.sh runs `apply` automatically when the profile exists.
//
// A profile holds: agents { name: { model, thinking } }, allow (the model
// scope) and families (extra family rules). `apply` only replaces what the
// profile defines, then models-lint decides (D31).
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { homedir } from "node:os";
import { effectiveAgents, userSettingsFile } from "./effective-models.mjs";

const AGENTS_DIR = ".pi/agents/factory";
const SETTINGS = ".pi/settings.json";
const FAMILIES = ".factory/model-families.json";
const argv = process.argv.slice(2);
const userMode = argv.includes("--user");
const [cmd, arg] = argv.filter((a) => a !== "--user");
const profile = arg || process.env.PI_FACTORY_MODELS || join(homedir(), ".pi-factory", "models.json");
const placeholder = (v) => /[<>]/.test(String(v ?? ""));
// An agent newer than the profile gets a model without anyone editing the
// profile: the first of the agents closest to its role whose model is pinned
// (not a floating alias) and, for a judge, of another family than what it
// judges. The choice is written into the profile, said once, and the profile
// stays the place to change it.
const STAND_IN = {
  "factory-architect": { from: ["factory-designer", "factory-investigator", "factory-contract-author", "factory-worker-heavy"] },
  "factory-strategy-critic": { from: ["factory-reviewer", "factory-validator", "factory-code-steward", "factory-contract-critic"], judges: "factory-architect" },
};
const FLOATING = /(^|[\/:._-])(latest|current|default|stable|preview)$/i;
function familyOf(p, id) {
  const pkg = join(dirname(new URL(import.meta.url).pathname), "..", "..", FAMILIES);
  const fams = [...(p.families ?? []), ...(existsSync(FAMILIES) ? readJson(FAMILIES).families ?? [] : []), ...(existsSync(pkg) ? readJson(pkg).families ?? [] : [])];
  const glob = (m) => new RegExp("^" + m.toLowerCase().replace(/[.+?^$(){}|[\]\\]/g, "\\$&").replace(/\*/g, ".*") + "$");
  return fams.find((f) => f?.match && glob(f.match).test(String(id).toLowerCase()))?.family;
}
function withStandIns(p) {
  p.agents = p.agents ?? {};
  const added = [];
  for (const [name, { from, judges }] of Object.entries(STAND_IN)) {
    const a = p.agents[name];
    if (a?.model && !placeholder(a.model)) continue;
    const judged = judges && p.agents[judges]?.model, judgedFam = judged && familyOf(p, judged);
    const cands = from.map((f) => ({ f, a: p.agents[f] })).filter((c) => c.a?.model && !placeholder(c.a.model));
    const ok = (c) => !FLOATING.test(c.a.model) && !(judgedFam && familyOf(p, c.a.model) === judgedFam);
    const pick = cands.find(ok) ?? cands.find((c) => !(judgedFam && familyOf(p, c.a.model) === judgedFam)) ?? cands[0];
    if (!pick) continue;
    p.agents[name] = { ...pick.a };
    const why = FLOATING.test(pick.a.model) ? " (a floating alias: no pinned candidate; pin one)" : "";
    added.push(`${name}: not in the profile, given ${pick.f}'s model (${pick.a.model})${why}`);
  }
  if (added.length && existsSync(profile)) {
    const raw = readJson(profile);
    raw.agents = { ...(raw.agents ?? {}) };
    for (const n of Object.keys(STAND_IN)) if (p.agents[n] && !(raw.agents[n]?.model && !placeholder(raw.agents[n].model))) raw.agents[n] = p.agents[n];
    writeFileSync(`${profile}.bak`, readFileSync(profile));
    writeFileSync(profile, JSON.stringify(raw, null, 2) + "\n");
    added.push(`written to ${profile}: edit it there to choose another`);
  }
  for (const l of added) console.log(l);
  return p;
}
const readJson = (f) => JSON.parse(readFileSync(f, "utf8"));

function agentFiles() {
  if (!existsSync(AGENTS_DIR)) { console.error(`no ${AGENTS_DIR}: run from a repo with the factory copied in, or use --user`); process.exit(2); }
  return readdirSync(AGENTS_DIR).filter((f) => f.endsWith(".md")).map((f) => join(AGENTS_DIR, f));
}
function field(text, key) {
  const fm = text.match(/^---\n([\s\S]*?)\n---/);
  return fm ? (fm[1].match(new RegExp(`^${key}:\\s*(.*)$`, "m")) || [])[1]?.trim() : undefined;
}

if (cmd === "capture") {
  const agents = {};
  for (const a of effectiveAgents()) {                 // D92: what really runs, overrides included
    const { name, model, thinking } = a;
    if (!name || !model || placeholder(model)) continue;
    agents[name] = thinking ? { model, thinking } : { model };
  }
  if (!Object.keys(agents).length) { console.error("no configured models here (only placeholders): nothing to capture"); process.exit(1); }
  // Merge into the existing profile: what this place doesn't define (no model
  // scope, no families file: the factory's own folder, a mirror) is kept, never
  // emptied. Captured agents win; agents only in the profile stay.
  const prev = existsSync(profile) ? readJson(profile) : {};
  const allow = ((existsSync(SETTINGS) ? readJson(SETTINGS).subagents?.modelScope?.allow : []) ?? []).filter((a) => !placeholder(a));
  const families = (existsSync(FAMILIES) ? readJson(FAMILIES).families : []) ?? [];
  const kept = [];
  if (!allow.length && prev.allow?.length) kept.push("model scope");
  if (!families.length && prev.families?.length) kept.push("families");
  const onlyPrev = Object.keys(prev.agents ?? {}).filter((n) => !(n in agents));
  if (onlyPrev.length) kept.push(`agents ${onlyPrev.join(", ")}`);
  const merged = { ...prev, agents: { ...(prev.agents ?? {}), ...agents }, allow: allow.length ? allow : prev.allow ?? [], families: families.length ? families : prev.families ?? [] };
  mkdirSync(dirname(profile), { recursive: true });
  if (existsSync(profile)) writeFileSync(`${profile}.bak`, readFileSync(profile));
  writeFileSync(profile, JSON.stringify(merged, null, 2) + "\n");
  console.log(`captured ${Object.keys(agents).length} agents → ${profile}${kept.length ? ` (kept from the profile: ${kept.join("; ")})` : ""}`);
} else if (cmd === "apply" && userMode) {
  if (!existsSync(profile)) { console.error(`no profile at ${profile} (create it with: capture, from a configured repo)`); process.exit(1); }
  const p = withStandIns(readJson(profile)), file = userSettingsFile();
  const s = existsSync(file) ? readJson(file) : {};
  const sub = (s.subagents = s.subagents ?? {});
  const ov = (sub.agentOverrides = sub.agentOverrides ?? {});
  let set = 0;
  for (const [name, a] of Object.entries(p.agents ?? {})) {
    if (!a?.model || placeholder(a.model)) continue;
    ov[name] = { ...(ov[name] ?? {}), model: a.model, ...(a.thinking ? { thinking: a.thinking } : {}) };
    set++;
  }
  if (Array.isArray(p.allow) && p.allow.length) sub.modelScope = { ...(sub.modelScope ?? {}), enforce: true, allow: p.allow };
  mkdirSync(dirname(file), { recursive: true });
  if (existsSync(file)) writeFileSync(`${file}.bak`, readFileSync(file));
  writeFileSync(file, JSON.stringify(s, null, 2) + "\n");
  console.log(`applied ${profile} to ${file}: ${set} agents (agentOverrides)${sub.modelScope?.allow ? ", model scope" : ""}`);
  if (Array.isArray(p.families) && p.families.length) console.log("families: sync-mirror.sh --projects adds the profile's rules to each project (or run apply, without --user, in a project)");
} else if (cmd === "apply") {
  // The factory's own source is public and shared: one machine's models don't belong in it.
  let own = ""; try { own = JSON.parse(readFileSync("package.json", "utf8")).name || ""; } catch {}
  if (/(^|\/)pi-factory$/.test(own) && existsSync("scripts/factory/next.sh") && process.env.FACTORY_APPLY_IN_SOURCE !== "1") {
    console.error("this is the factory's source: models here would be one machine's settings in a shared repo. Use: factory models apply --user (then sync-mirror applies it to the projects)");
    process.exit(2);
  }
  if (!existsSync(profile)) { console.error(`no profile at ${profile} (create it with: capture, from a configured repo)`); process.exit(1); }
  const p = withStandIns(readJson(profile));
  let set = 0;
  if (!existsSync(AGENTS_DIR)) console.log("agents: on the installed package here; their models come from apply --user");
  for (const f of existsSync(AGENTS_DIR) ? agentFiles() : []) {
    const text = readFileSync(f, "utf8");
    const a = p.agents?.[field(text, "name")];
    if (!a?.model) continue;
    const out = text.replace(/^---\n([\s\S]*?)\n---/, (_, fm) => {
      let lines = fm.split("\n").filter((l) => !/^(model|thinking|fallbackModels):/.test(l));
      const at = Math.max(1, lines.findIndex((l) => /^description:/.test(l)) + 1);
      lines.splice(at, 0, `model: ${a.model}`, ...(a.thinking ? [`thinking: ${a.thinking}`] : []));
      return `---\n${lines.join("\n")}\n---`;
    });
    writeFileSync(f, out); set++;
  }
  if (Array.isArray(p.allow) && p.allow.length && existsSync(SETTINGS)) {
    const s = readJson(SETTINGS);
    s.subagents = s.subagents ?? {};
    s.subagents.modelScope = { ...(s.subagents.modelScope ?? {}), enforce: true, allow: p.allow };
    writeFileSync(SETTINGS, JSON.stringify(s, null, 2) + "\n");
  }
  if (Array.isArray(p.families) && existsSync(FAMILIES)) {
    const fam = readJson(FAMILIES);
    const known = new Set(fam.families.map((x) => x.match.toLowerCase()));
    const extra = p.families.filter((x) => x?.match && !known.has(x.match.toLowerCase()));
    fam.families = [...extra, ...fam.families];
    writeFileSync(FAMILIES, JSON.stringify(fam, null, 2) + "\n");
  }
  console.log(`applied ${profile}: ${set} agents set`);
} else {
  console.error("usage: models-profile.mjs capture [profile] | apply [--user] [profile]");
  process.exit(2);
}
