#!/usr/bin/env node
// Per-machine models profile: configure the factory's models once, reuse them
// in every repo. The profile lives outside any repo (model ids and providers
// are yours, not the template's), by default ~/.pi-factory/models.json.
//
// Usage (from a target repo root):
//   node scripts/factory/models-profile.mjs capture [profile]   # save this repo's configured models
//   node scripts/factory/models-profile.mjs apply   [profile]   # write them into this repo
// install-into.sh runs `apply` automatically when the profile exists.
//
// A profile holds: agents { name: { model, thinking } }, allow (the model
// scope) and families (extra family rules). `apply` only replaces what the
// profile defines, then models-lint decides (D31).
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { homedir } from "node:os";

const AGENTS_DIR = ".pi/agents/factory";
const SETTINGS = ".pi/settings.json";
const FAMILIES = ".factory/model-families.json";
const [cmd, arg] = process.argv.slice(2);
const profile = arg || process.env.PI_FACTORY_MODELS || join(homedir(), ".pi-factory", "models.json");
const placeholder = (v) => /[<>]/.test(String(v ?? ""));
const readJson = (f) => JSON.parse(readFileSync(f, "utf8"));

function agentFiles() {
  if (!existsSync(AGENTS_DIR)) { console.error(`no ${AGENTS_DIR}: run from a repo with the factory installed`); process.exit(2); }
  return readdirSync(AGENTS_DIR).filter((f) => f.endsWith(".md")).map((f) => join(AGENTS_DIR, f));
}
function field(text, key) {
  const fm = text.match(/^---\n([\s\S]*?)\n---/);
  return fm ? (fm[1].match(new RegExp(`^${key}:\\s*(.*)$`, "m")) || [])[1]?.trim() : undefined;
}

if (cmd === "capture") {
  const agents = {};
  for (const f of agentFiles()) {
    const text = readFileSync(f, "utf8");
    const name = field(text, "name"), model = field(text, "model"), thinking = field(text, "thinking");
    if (!name || !model || placeholder(model)) continue;
    agents[name] = thinking ? { model, thinking } : { model };
  }
  if (!Object.keys(agents).length) { console.error("no configured models here (only placeholders): nothing to capture"); process.exit(1); }
  const allow = (existsSync(SETTINGS) ? readJson(SETTINGS).subagents?.modelScope?.allow : []) ?? [];
  const families = existsSync(FAMILIES) ? readJson(FAMILIES).families : [];
  mkdirSync(dirname(profile), { recursive: true });
  writeFileSync(profile, JSON.stringify({ agents, allow: allow.filter((a) => !placeholder(a)), families }, null, 2) + "\n");
  console.log(`captured ${Object.keys(agents).length} agents → ${profile}`);
} else if (cmd === "apply") {
  if (!existsSync(profile)) { console.error(`no profile at ${profile} (create it with: capture, from a configured repo)`); process.exit(1); }
  const p = readJson(profile);
  let set = 0;
  for (const f of agentFiles()) {
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
  console.error("usage: models-profile.mjs capture|apply [profile]");
  process.exit(2);
}
