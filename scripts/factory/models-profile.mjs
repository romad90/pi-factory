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
  const p = readJson(profile), file = userSettingsFile();
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
  if (Array.isArray(p.families) && p.families.length) console.log("families: run apply (without --user) in each project to add the profile's rules to .factory/model-families.json");
} else if (cmd === "apply") {
  if (!existsSync(profile)) { console.error(`no profile at ${profile} (create it with: capture, from a configured repo)`); process.exit(1); }
  const p = readJson(profile);
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
