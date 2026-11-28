#!/usr/bin/env node
// Prompt caching per run and per model (B13, P20). An agent resends its whole
// conversation every turn; with caching the provider bills the part it has seen
// at a fraction of the price. One model family on a route can read nothing from
// cache while the others read most of their input from it, and nothing showed
// it: a contract author paid $13.06 for 2.1M uncached input tokens.
//
// Usage: node cache.mjs <archive-root>          the share per model, every mission
//        node cache.mjs --warn <archive-root>   one line per model whose runs read
//                                               nothing from cache over several turns
//                                               (doctor); prints nothing otherwise
// Reads only run.json usage (input, cacheRead, cacheWrite, turns). It never
// changes a model or a route: that is the route owner's to fix.
import { readFileSync, readdirSync, existsSync, statSync, realpathSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

// A model whose runs read 0 from cache is named once it has this many runs of
// at least MIN_TURNS turns each: one short run can end before a cache is used.
export const MIN_RUNS = 2, MIN_TURNS = 3;
const n = (x) => (Number.isFinite(x) ? x : 0);

export function cacheShare(u) {
  u = u || {};
  const fresh = n(u.input), read = n(u.cacheRead), write = n(u.cacheWrite), total = fresh + read + write;
  return { fresh, read, write, total, share: total ? Math.round((read / total) * 100) / 100 : null };
}

// The thinking level is not part of the model: "x/y:high" and "x/y" are one model.
export const modelOf = (m) => String(m || "?").replace(/:(off|minimal|low|medium|high|xhigh|max)$/, "");

const readJson = (f) => { try { return JSON.parse(readFileSync(f, "utf8")); } catch { return null; } };
const isDir = (d) => { try { return statSync(d).isDirectory(); } catch { return false; } };

// Every archived run with usage: <root>/<mission>/<run-folder>/run.json.
export function scanArchive(root) {
  const out = [];
  if (!existsSync(root)) return out;
  for (const mission of readdirSync(root).sort()) {
    const md = join(root, mission);
    if (!isDir(md)) continue;
    for (const run of readdirSync(md).sort()) {
      const j = isDir(join(md, run)) && readJson(join(md, run, "run.json"));
      if (j && j.usage && typeof j.usage === "object") out.push({ mission, run: j.run || run, agent: j.agent || "?", model: j.model || "", usage: j.usage });
    }
  }
  return out;
}

export function cacheByModel(runs) {
  const by = new Map();
  for (const r of runs) {
    const c = cacheShare(r.usage);
    if (!c.total) continue;
    const m = by.get(modelOf(r.model)) || { model: modelOf(r.model), runs: 0, turns: 0, total: 0, cacheRead: 0, long: 0, longRead: 0 };
    const turns = n(r.usage.turns);
    m.runs++; m.turns += turns; m.total += c.total; m.cacheRead += c.read;
    if (turns >= MIN_TURNS) { m.long++; m.longRead += c.read; }
    by.set(m.model, m);
  }
  return [...by.values()].sort((a, b) => b.total - a.total).map(({ long, longRead, ...m }) => ({
    ...m, share: m.total ? Math.round((m.cacheRead / m.total) * 100) / 100 : null, noCache: long >= MIN_RUNS && longRead === 0,
  }));
}

export const k = (x) => (x >= 1e6 ? `${(x / 1e6).toFixed(2)}M` : x >= 1000 ? `${(x / 1000).toFixed(1)}k` : String(x));
export const pct = (s) => (s === null ? "-" : `${Math.round(s * 100)}%`);

export function table(models) {
  const lines = [["  model".padEnd(40), "runs".padStart(5), "turns".padStart(6), "input".padStart(9), "cached".padStart(9), "share".padStart(6)].join(" ")];
  for (const m of models)
    lines.push([`  ${m.model}`.slice(0, 40).padEnd(40), String(m.runs).padStart(5), String(m.turns).padStart(6), k(m.total).padStart(9), k(m.cacheRead).padStart(9), pct(m.share).padStart(6)].join(" ")
      + (m.noCache ? "  no cache read" : ""));
  return lines;
}

// Batch 2026-11-28: $21.70 of a $33.96 batch was one Claude model reached
// through a custom OpenAI-compatible provider. Pi sends Anthropic's cache
// markers on its own only for the provider named "openrouter"; any other
// needs the model's compat setting. The warning names that setting.
const CLAUDE_HINT = `. For a Claude model behind an OpenAI-compatible provider, set "compat": {"cacheControlFormat": "anthropic"} on the model in ~/.pi/agent/models.json`;
export const warning = (m) => `${m.model}: ${m.runs} runs, ${m.turns} turns, ${k(m.total)} input, none read from cache: every turn pays the whole conversation at the full input price (the route's caching for this model, not the factory)`
  + (/anthropic|claude/i.test(m.model) ? CLAUDE_HINT : "");

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  const args = process.argv.slice(2), warn = args.includes("--warn");
  const root = args.find((a) => !a.startsWith("--"));
  if (!root) { console.error("usage: cache.mjs [--warn] <archive-root>"); process.exit(2); }
  const models = cacheByModel(scanArchive(root));
  if (warn) { for (const m of models.filter((x) => x.noCache)) console.log(warning(m)); process.exit(0); }
  if (!models.length) { console.log("cache: no archived run with usage yet"); process.exit(0); }
  console.log("Cache by model (input + cache read + cache write; share: the part read from cache)");
  for (const l of table(models)) console.log(l);
}
