#!/usr/bin/env node
// One-time migration (D31 revised): pi-subagents only accepts builtin agent
// names in settings `agentOverrides`; project agents there crash agent
// discovery ("Builtin override 'factory-…'"). Models move into each factory
// agent's frontmatter (model, thinking), which the package
// documents as authoritative. Idempotent.
//
// Usage (repo root): node scripts/factory/migrate-models.mjs
import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";

const SETTINGS = ".pi/settings.json";
const DIR = ".pi/agents/factory";

const settings = existsSync(SETTINGS) ? JSON.parse(readFileSync(SETTINGS, "utf8")) : {};
const overrides = settings.subagents?.agentOverrides ?? {};
let moved = 0;

for (const file of readdirSync(DIR).filter((f) => f.endsWith(".md"))) {
  const path = join(DIR, file);
  const text = readFileSync(path, "utf8");
  const m = text.match(/^---\n([\s\S]*?)\n---/);
  if (!m) continue;
  const name = (m[1].match(/^name:\s*(.+)$/m) || [])[1]?.trim();
  const o = overrides[name];
  if (!o) continue;
  let fm = m[1].split("\n").filter((l) => !/^(model|fallbackModels|thinking):/.test(l));
  const lines = [];
  if (o.model) lines.push(`model: ${o.model}`);
  if (o.thinking) lines.push(`thinking: ${o.thinking}`);
  const at = fm.findIndex((l) => l.startsWith("description:"));
  fm.splice(at + 1, 0, ...lines);
  writeFileSync(path, text.replace(m[0], `---\n${fm.join("\n")}\n---`));
  delete overrides[name];
  moved++;
  console.log(`  ${name}: ${o.model}`);
}

if (settings.subagents) {
  if (Object.keys(overrides).length === 0) delete settings.subagents.agentOverrides;
  writeFileSync(SETTINGS, JSON.stringify(settings, null, 2) + "\n");
}
console.log(moved ? `Moved ${moved} agent model(s) into frontmatter; agentOverrides cleaned.` : "Nothing to migrate (models already in frontmatter).");
