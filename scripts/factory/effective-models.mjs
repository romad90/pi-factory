#!/usr/bin/env node
// The model and thinking level each factory agent really runs with (D92), as
// pi-subagents 0.76.1 resolves them: the agent file's frontmatter, then the
// user's `subagents.agentOverrides.<name>` (~/.pi/agent/settings.json, or
// $PI_CODING_AGENT_DIR/settings.json), then the project's (.pi/settings.json).
// A project with the factory copied in has its agents in .pi/agents/factory;
// a project on the installed package (P11) has none, and the package's own are
// used. Every script that names a model (verdicts, runs.tsv, lint, probe)
// reads it from here, so a per-machine override is what they report.
//
// Usage: node scripts/factory/effective-models.mjs [--json]   (TSV: name, model, thinking, file)
// Not resolved: agentOverridesByProvider and subagents.defaultModel/defaultThinking.
import { readFileSync, readdirSync, existsSync, realpathSync } from "node:fs";
import { join, dirname } from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";

const here = dirname(realpathSync(fileURLToPath(import.meta.url)));
export const PACKAGE_ROOT = join(here, "..", "..");

export function agentsDir() {
  if (process.env.FACTORY_AGENTS_DIR) return process.env.FACTORY_AGENTS_DIR;
  if (existsSync(".pi/agents/factory")) return ".pi/agents/factory";
  return join(PACKAGE_ROOT, ".pi", "agents", "factory");
}
export const userSettingsFile = () => join(process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent"), "settings.json");
const readJson = (f) => { try { return JSON.parse(readFileSync(f, "utf8")); } catch { return {}; } };

// subagents settings as pi-subagents merges them: user first, project wins.
export function subagentSettings() {
  const user = readJson(userSettingsFile()).subagents || {};
  const project = readJson(".pi/settings.json").subagents || {};
  return { user, project, merged: { ...user, ...project } };
}

export function frontmatter(file) {
  const m = readFileSync(file, "utf8").match(/^---\n([\s\S]*?)\n---/);
  const out = {};
  if (m) for (const line of m[1].split("\n")) {
    const kv = line.match(/^([A-Za-z][\w-]*):\s*(.*)$/);
    if (kv) out[kv[1]] = kv[2].trim();
  }
  return out;
}

export function effectiveAgents(dir = agentsDir()) {
  if (!existsSync(dir)) return [];
  const { user, project } = subagentSettings();
  return readdirSync(dir).filter((f) => f.endsWith(".md")).sort().map((f) => {
    const file = join(dir, f), fm = frontmatter(file), name = fm.name || f.replace(/\.md$/, "");
    let model = fm.model || "", thinking = fm.thinking || "", source = model ? "file" : "";
    for (const [scope, s] of [["user", user], ["project", project]]) {
      const o = s.agentOverrides && s.agentOverrides[name];
      if (!o || typeof o !== "object") continue;
      if (o.model === false) { model = ""; source = scope; } else if (typeof o.model === "string" && o.model) { model = o.model; source = scope; }
      if (typeof o.thinking === "string" && o.thinking) thinking = o.thinking;
    }
    return { name, model, thinking, source, file, fm };
  });
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  const list = effectiveAgents();
  if (process.argv.includes("--json")) console.log(JSON.stringify(list.map(({ fm, ...a }) => a), null, 2));
  else for (const a of list) console.log([a.name, a.model, a.thinking, a.file].join("\t"));
}
